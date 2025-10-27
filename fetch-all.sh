#!/usr/bin/env bash
set -euo pipefail

# --- Safe locale: try several UTF-8s (macOS 沒有 C.UTF-8) ---
for L in C.UTF-8 en_US.UTF-8 zh_TW.UTF-8; do
  if locale -a 2>/dev/null | grep -qi "^${L}$"; then
    export LC_ALL="$L" LANG="$L"
    break
  fi
done


# -------- 先自我消毒：移除腳本內的 BOM/CR/NBSP，避免 $KEYWORD 類錯誤 --------
if [ -w "$0" ]; then
  perl -i -CS -pe 's/\x{FEFF}//g; s/\r$//; s/\x{00A0}/ /g' "$0" 2>/dev/null || true
fi

# --- 安全的本地環境（避免編碼亂流） ---
export LC_ALL=C.UTF-8 2>/dev/null || true
export LANG=C.UTF-8 2>/dev/null || true

strip_cr_bom() { perl -CS -pe 's/\x{FEFF}//g; s/\r$//; s/\x{00A0}/ /g' ; }

# --- 互動輸入 ---
read -r -p "請輸入關鍵字（例如：SRE 工程師）: " KEYWORD_RAW
KEYWORD="$(printf '%s' "$KEYWORD_RAW" | strip_cr_bom | sed 's/[[:space:]]*$//')"

read -r -p "最多抓幾� �？(直接按 Enter 表示抓全部) " MAX_PAGES_INPUT_RAW
MAX_PAGES_INPUT="$(printf '%s' "${MAX_PAGES_INPUT_RAW:-}" | strip_cr_bom)"

# --- 可調參數 ---
UA_DEFAULT='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36'
UA="${UA:-$UA_DEFAULT}"
RO="${RO:-0}"
ORDER="${ORDER:-15}"
ASC="${ASC:-0}"
MODE="${MODE:-s}"
JOBSOURCE="${JOBSOURCE:-2018indexpoc}"

# --- URL 編碼 ---
urlencode() {
  if command -v jq >/dev/null 2>&1; then
    jq -sRr @uri
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$@" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.stdin.read().rstrip("\n")))
PY
  else
    sed 's/ /%20/g'
  fi
}

KEYWORD_ENC="$(printf '%s' "$KEYWORD" | urlencode)"

# --- 基底查詢 ---
base_qs="keyword=${KEYWORD_ENC}&ro=${RO}&order=${ORDER}&asc=${ASC}&mode=${MODE}&jobsource=${JOBSOURCE}"
base_api="https://www.104.com.tw/jobs/search/list?${base_qs}"
base_ref="https://www.104.com.tw/jobs/search/?${base_qs}"

# --- 先取總� �數 ---
TOTAL="$(curl -s "${base_api}&page=1" \
  -H 'Accept: application/json, text/plain, */*' \
  -H 'Accept-Language: zh-TW,zh;q=0.9' \
  -H "Referer: ${base_ref}&page=1" \
  -H 'Origin: https://www.104.com.tw' \
  -H 'X-Requested-With: XMLHttpRequest' \
  -H "User-Agent: ${UA}" --compressed | jq -r '.data.totalPage // 0')"

if [[ ! "$TOTAL" =~ ^[0-9]+$ || "$TOTAL" -le 0 ]]; then
  echo "查無資料或被擋（totalPage=$TOTAL）。請換關鍵字或檢查 headers。" >&2
  exit 1
fi

# 覆寫最多� �數（若使用者有輸入）
if [[ -n "$MAX_PAGES_INPUT" ]]; then
  if [[ "$MAX_PAGES_INPUT" =~ ^[0-9]+$ && "$MAX_PAGES_INPUT" -gt 0 ]]; then
    (( MAX_PAGES_INPUT < TOTAL )) && TOTAL="$MAX_PAGES_INPUT"
  else
    echo "最多� �數輸入無效，將抓全部 $TOTAL � �。"
  fi
fi

# --- 產生兩行原則的 pipet 規則 ---
TS="$(date +%Y%m%d_%H%M)"
SAFEKW="$(printf '%s' "$KEYWORD" | tr ' /' '__' | strip_cr_bom)"
OUT_PIPET="104-${SAFEKW}-${TS}.pipet"
OUT_JSONL="104-${SAFEKW}-${TS}.jsonl"

: > "$OUT_PIPET"
for p in $(seq 1 "$TOTAL"); do
  printf "curl '%s&page=%d' -H 'Accept: application/json, text/plain, */*' -H 'Accept-Language: zh-TW,zh;q=0.9' -H 'Referer: %s&page=%d' -H 'Origin: https://www.104.com.tw' -H 'X-Requested-With: XMLHttpRequest' -H 'User-Agent: %s' --compressed\n" \
    "$base_api" "$p" "$base_ref" "$p" "$UA" >> "$OUT_PIPET"
  printf "@this | jq -c '.data.list[] | {date:.appearDate,date_desc:.appearDateDesc,job_id:.jobNo,title:.jobName,company:.custName,industry:.coIndustryDesc,location:.jobAddrNoDesc,address:.jobAddress,mrt:.mrtDesc,landmark:.landmark,salary:.salaryDesc,salaryLow:.salaryLow,salaryHigh:.salaryHigh,apply:.applyDesc,apply_cnt:(.applyCnt|tonumber?),experience:.periodDesc,education:.optionEdu,majors:(if (.major|type==\"array\" and (.major|length>0)) then .major else empty end),source:.jobsource,job_url:(if .link.job? then \"https:\"+.link.job else \"https://www.104.com.tw/job/\"+(.jobNo|tostring) end),company_url:(if .link.cust? then \"https:\"+.link.cust else empty end)} | with_entries(select(.value!=null and (((.value|type)==\"string\" and .value!=\"\") or ((.value|type)==\"number\") or ((.value|type)==\"array\" and (.value|length>0)) or ((.value|type)==\"object\" and (.value|length>0)))))'\n\n" >> "$OUT_PIPET"
done

# 去除 pipet 檔中的 BOM/CR，避免 "Found block <nil)"，並確認首字
perl -i -CS -pe 's/\x{FEFF}//g; s/\r$//' "$OUT_PIPET"
first_char="$(head -c1 "$OUT_PIPET" || true)"
if [ "$first_char" != "c" ]; then
  # 去掉檔首可能出現的空白/空行
  awk 'NR==1 && $0=="" {next} {print}' "$OUT_PIPET" > "$OUT_PIPET.tmp" && mv "$OUT_PIPET.tmp" "$OUT_PIPET"
fi

# --- 執行 pipet ---
pipet --json -v "$OUT_PIPET" > "$OUT_JSONL"

# --- 統計輸出筆數 ---
LINES="$(wc -l < "$OUT_JSONL" | awk '{print $1}')"
echo "OK: 關鍵字「${KEYWORD}」已輸出 ${LINES} 筆到 ${OUT_JSONL}（共處理 ${TOTAL} � �）"
echo "pipet 規則檔在：$OUT_PIPET"
echo

echo "=== 熱門技能詞（Top 20）==="
# ====== CKIP 斷詞 + POS 的技能詞抽取（失敗自動 fallback 正則 + 除錯）======
python3 -X utf8 - "$OUT_JSONL" <<'PY'
# -*- coding: utf-8 -*-
import os, sys, json, re
from collections import Counter

# 優先用 argv[1]；找不到再看環境變數；最後嘗試自動尋找最近的 104-*.jsonl
path = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("OUT_JSONL")
if not path:
    import glob, os
    candidates = sorted(glob.glob("104-*.jsonl"), key=os.path.getmtime, reverse=True)
    if candidates:
        path = candidates[0]
if not path:
    print("[ERROR] 找不到輸入檔，請設定 OUT_JSONL 或傳入檔名參數。")
    sys.exit(1)

topn = int(os.environ.get("TOPN","20"))

def walk(x):
    if isinstance(x, dict):
        yield x
        for v in x.values():
            yield from walk(v)
    elif isinstance(x, list):
        for v in x:
            yield from walk(v)

def load_any(p):
    # 1) 嘗試整檔就是一個 JSON
    try:
        with open(p, 'r', encoding='utf-8', errors='replace') as f:
            data = json.load(f)
        print(f"[DEBUG] input={p} mode=single-JSON")
        return data
    except Exception:
        pass
    # 2) NDJSON：逐行 parse
    arr, parsed = [], 0
    with open(p, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                arr.append(json.loads(line))
                parsed += 1
            except Exception:
                # 忽略像是 '],' 之類行
                continue
    print(f"[DEBUG] input={p} mode=ndjson parsed_lines={parsed}")
    return arr

re_html = re.compile(r"<[^>]+>")

data = load_any(path)

# 抽出含 title/描述 的物件
records = []
dicts_seen = 0
for d in walk(data):
    if isinstance(d, dict):
        dicts_seen += 1
        if any(k in d for k in ("title","jobName","descSnippet","descWithoutHighlight","description")):
            records.append(d)

print(f"[DEBUG] dicts_seen={dicts_seen}, job_like_dicts={len(records)}")

# 組語料
texts=[]
for o in records:
    title = o.get("title") or o.get("jobName") or ""
    desc  = o.get("descSnippet") or o.get("descWithoutHighlight") or o.get("description") or ""
    t = (title + " " + desc)
    t = re_html.sub(" ", t).replace("&lt;","<").replace("&gt;",">").replace("&amp;","&")
    t = t.replace("\\n"," ").replace("\n"," ")
    if t.strip():
        texts.append(t)

print(f"[DEBUG] texts_nonempty={len(texts)}")
if not texts:
    print("=== 熱門技能詞（Top %d）[無語料]===" % topn)
    sys.exit(0)

# 詞抽取：先試 CKIP，失敗就 regex fallback
terms = None
ckip_ok = False
try:
    from ckip_transformers.nlp import CkipWordSegmenter, CkipPosTagger  # type: ignore
    ws  = CkipWordSegmenter(model="bert-base")
    pos = CkipPosTagger(model="bert-base")
    ws_result  = ws(texts, batch_size=8)
    pos_result = pos(ws_result, batch_size=8)

    alpha = re.compile(r"^[A-Za-z]{2,}$")         # 純英文、長度≥2
    has_digit = re.compile(r"[0-9]")              # 去掉含數字
    terms=[]
    for toks,tags in zip(ws_result,pos_result):
        for w,t in zip(toks,tags):
            if not w or has_digit.search(w):
                continue
            # 英文：純字母且長度>1 → 全轉小寫計數
            if alpha.match(w):
                terms.append(w.lower())
                continue
            # 中文：名詞 + 2~6 個漢字
            w2 = w.strip()
            if t.startswith('N') and 2 <= len(w2) <= 6 and all('\u4e00'<=c<='\u9fff' for c in w2):
                terms.append(w2)
    ckip_ok = True
except Exception as e:
    print(f"[DEBUG] CKIP unavailable ({e}); using regex fallback.")
    alpha = re.compile(r"\b[A-Za-z]{2,}\b")
    han   = re.compile(r"[\u4e00-\u9fff]{2,6}")
    has_digit = re.compile(r"[0-9]")
    terms=[]
    for t in texts:
        # 英文（去數字、已保證無標點；以非字元切，再匹配）
        terms += [w.lower() for w in alpha.findall(t) if not has_digit.search(w)]
        # 中文（2~6 連續漢字）
        terms += han.findall(t)

from collections import Counter
freq = Counter(terms)

print("=== 熱門技能詞（Top {}）{}===".format(topn, "" if ckip_ok else "[fallback]"))
for term, cnt in freq.most_common(topn):
    print("{:5d} {}".format(cnt, term))
PY
# ====== /技能詞� � ======





echo "=== 薪資統計（以 salaryLow/salaryHigh 解析，單位：元）==="

vals="$(jq -r '
  recurse(.[]?; .) | select(type=="object")
  | [ (.salaryLow // "0"), (.salaryHigh // "0") ]
  | map(tostring | gsub(",|\\s";"") | (tonumber? // 0))
  | @tsv
' "$OUT_JSONL" | awk -F'\t' '
  {
    low=$1+0; high=$2+0;
    # 忽略 9999999（「以上」）與明顯不合理高值（> 5,000,000）
    if(high==9999999 || high>5000000) high=0;
    if(low==9999999  || low>5000000)  low=0;
    if(low+high>0) print low "\t" high;
  }' || true)"

if [[ -z "${vals}" ]]; then
  echo "（沒有可用的 salaryLow/salaryHigh 數值，可能多為「待遇面議」。）"
else
  printf "%s\n" "$vals" | awk -F'\t' '
    BEGIN{lc=0; lsum=0; lmin=""; lmax=0; hc=0; hsum=0; hmin=""; hmax=0}
    {
      low=$1+0; high=$2+0;
      if(low>0){lc++; lsum+=low; if(lmin==""||low<lmin){lmin=low} if(low>lmax){lmax=low}}
      if(high>0){hc++; hsum+=high; if(hmin==""||high<hmin){hmin=high} if(high>hmax){hmax=high}}
    }
    END{
      if(lc>0){ printf("LOW ：有明確下限 %d 筆；平均 %.0f；最低 %d；最高 %d\n", lc, lsum/lc, lmin, lmax) }
      else    { print "LOW ：無明確下限數據" }
      if(hc>0){ printf("HIGH：有明確上限 %d 筆；平均 %.0f；最低 %d；最高 %d\n", hc, hsum/hc, hmin, hmax) }
      else    { print "HIGH：無明確上限數據" }
    }'
fi
echo



echo "=== 上限最高 Top 10 職缺（high desc）==="
jq -c '
  recurse(.[]?; .) | select(type=="object")
  | { title:   (.title   // .jobName),
      company: (.company // .custName),
      location, salary, job_url,
      high_raw: ((.salaryHigh // "0") | tostring | gsub(",|\\s";"") | tonumber? // 0)
    }
  | select(.high_raw>0 and .high_raw!=9999999 and .high_raw<=5000000)
  | .high = .high_raw
  | del(.high_raw)
' "$OUT_JSONL" \
| jq -s 'sort_by(-.high) | .[] | .title+" | "+.company+" | "+(.high|tostring)+" | "+(.job_url // "")' \
| head -n 10 || true
