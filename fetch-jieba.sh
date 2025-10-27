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

# 1) 組語料：title + 摘要，清掉 HTML/換行
corpus="$(
  jq -r '
    recurse(.[]?; .) | select(type=="object")
    | [ (.title // .jobName // ""),
        (.descSnippet // .descWithoutHighlight // .description // "")
      ] | join(" ")
      | gsub("\\\\n"; " ")
      | gsub("<[^>]+>"; "")
      | gsub("&lt;"; "<") | gsub("&gt;"; ">") | gsub("&amp;"; "&")
  ' "$OUT_JSONL" 2>/dev/null
)"

# 2) 直接產生候選詞（英文 tokens + 中文 2~4 連續漢字）
# 英文：非字母切割 → 至少2字母 → 全小寫（避免大小寫分裂）
eng_tokens="$(
  printf "%s\n" "$corpus" \
  | tr -cs 'A-Za-z' '\n' \
  | awk 'length($0)>1{print tolower($0)}'
)"

# 中文：抓 2~4 連續漢字片段
cn_tokens="$(
  printf "%s\n" "$corpus" \
  | perl -CS -Mutf8 -ne 'use utf8; while (/(\p{Han}{2,4})/g) { print "$1\n"; }'
)"

# 3) 合併、過濾（剔除含數字/標點——英文已處理，中文這裡再保險一次）、計數、Top 20
printf "%s\n%s\n" "$eng_tokens" "$cn_tokens" \
| awk 'NF>0 && $0 !~ /[0-9[:punct:]]/' \
| sort | uniq -c | sort -nr | head -n 20 \
| awk '{c=$1; $1=""; term=substr($0,2); printf("%5d %s\n", c, term)}' || true

echo





echo "=== 薪資統計（以 salaryLow/salaryHigh 解析，單位：元）==="

jq -r '
  recurse(.[]?; .) | select(type=="object")
  | [ (.salaryLow // "0"), (.salaryHigh // "0") ]
  | map(tostring | gsub(",|\\s";"") | (tonumber? // 0))
  | @tsv
' "$OUT_JSONL" \
| awk -F'\t' '
  {
    low=$1+0; high=$2+0;
    # 忽略 9999999（「以上」）與過高異常值（> 5,000,000）
    if(high==9999999 || high>5000000) high=0;
    if(low==9999999  || low>5000000)  low=0;

    if(low>0){lc++; lsum+=low; if(lmin==""||low<lmin){lmin=low} if(low>lmax){lmax=low}}
    if(high>0){hc++; hsum+=high; if(hmin==""||high<hmin){hmin=high} if(high>hmax){hmax=high}}
  }
  END{
    if(lc>0){ printf("LOW ：有明確下限 %d 筆；平均 %.0f；最低 %d；最高 %d\n", lc, lsum/lc, lmin, lmax) }
    else    { print "LOW ：無明確下限數據" }
    if(hc>0){ printf("HIGH：有明確上限 %d 筆；平均 %.0f；最低 %d；最高 %d\n", hc, hsum/hc, hmin, hmax) }
    else    { print "HIGH：無明確上限數據" }
  }'
echo





echo "=== 上限最高 Top 10 職缺（high desc）==="

jq -r '
  recurse(.[]?; .) | select(type=="object")
  | {
      title:   (.title   // .jobName // ""),
      company: (.company // .custName // ""),
      job_url: (if .job_url? then .job_url
                else if .link.job? then "https:"+.link.job
                else "https://www.104.com.tw/job/"+(.jobNo|tostring)
                end end),
      high:    ((.salaryHigh // "0") | tostring | gsub(",|\\s";"") | tonumber? // 0)
    }
  | select(.high>0 and .high!=9999999 and .high<=5000000)
  | [(.high|tostring), .title, .company, .job_url]
  | @tsv
' "$OUT_JSONL" \
| sort -t $'\t' -k1,1nr \
| head -n 10 \
| awk -F'\t' '{printf("%s | %s | %s | %s\n", $2, $3, $1, $4)}' || true
