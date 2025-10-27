# 💼 Vibe Coding Taiwan Job Bank Crawler

> 自動化爬取 **104 人力銀行** 公開職缺資料，進行職缺趨勢與技能關鍵字分析。  
> 支援中英混合技能詞彙統計、薪資上下限分析與 Top 職缺排行。

---

## 🧭 專案宗旨

本專案旨在：
- 蒐集公開職缺資料以觀察職場趨勢。  
- 分析熱門技能詞（支援中英文斷詞）。  
- 推動開源的就業市場資料科學研究。  

> ⚠️ 僅限教育、學術或非商業研究用途。  
> 不重製、不散布、不轉售任何原始職缺內容。

---

## ⚙️ 安裝與環境需求

### 🧩 系統需求
| 組件 | 最低版本 | 用途 |
|------|-----------|------|
| macOS / Linux / WSL | 任意 | 執行環境 |
| **bash** | 5+ | 主腳本語法 |
| **curl** | 7+ | 抓取 API |
| **jq** | 1.6+ | JSON 處理 |
| **pipet** | latest | 任務管線處理 |
| **Python3** | 3.8+ | 中文分詞與技能抽取 |
| **jieba** / **ckiptagger** | 最新 | 中文斷詞模組（自動 fallback） |

---

### 🧰 安裝指令

```bash
# 安裝必要套件
brew install jq curl python3 git

# 安裝 pipet（任一方式）
# 方式1：使用 Go
go install github.com/pomdtr/pipet@latest
# 方式2：使用 Homebrew
brew install pipet

# 安裝 Python 依賴
pip3 install jieba ckip-transformers tqdm
```

---

## 🚀 使用方式

```bash
bash fetch-all.sh
```

執行後系統會互動式詢問：

```
請輸入關鍵字（例如：SRE 工程師）: SRE工程師
最多抓幾頁？(直接按 Enter 表示抓全部) 5
```

---

## 📊 範例輸出結果

```
OK: 關鍵字「SRE工程師」已輸出 3095 筆到 104-SRE工程師-20251023_1551.jsonl（共處理 2 頁）

=== 熱門技能詞（Top 20）===
  10 linux
   9 aws
   5 mysql
   4 python
   4 docker
   4 kubernetes
   3 redis
   3 ansible
   3 gitlab
   3 GCP
   3 terraform
   2 DevOps
   2 Prometheus
   2 Grafana
   2 shell
   2 nginx
   2 elk
   2 sql
   2 postgresql
   2 nodejs

=== 薪資統計（以 salaryLow/salaryHigh 解析，單位：元）===
LOW ：有明確下限 19 筆；平均 91903；最低 36000；最高 780000  
HIGH：有明確上限 19 筆；平均 2234755；最低 45000；最高 9999999

=== 上限最高 Top 10 職缺 ===
SRE Engineer SRE工程師 | ＯＯ科技有限公司 | 9999999 |
Sr.SRE 工程師 | ＯＯ企業股份有限公司 | 9999999 |
SRE網站可靠性工程師 | ＯＯ資通股份有限公司 | 9999999 |
...
```

---

## 🧠 模組特色

| 模組 | 功能 | 描述 |
|------|------|------|
| **pipet** | 兩行規則批量爬取 | 高速、低負載、可追蹤進度 |
| **jq** | 精準欄位抽取 | 自動清除空值與無效欄位 |
| **jieba + ckiptagger** | 雙引擎中文分詞 | 支援 AI 模型詞性分析 |
| **技能詞濾波器** | 自動剔除數字、標點、無效詞 | 僅統計可讀技術名詞 |
| **薪資分析器** | 解析上下限 + 平均 | 自動排除面議或錯誤值 |

---

## 🛡️ 爬蟲安全策略（Crawler Safety Policy）

> 詳細版見 [`CRAWLER_POLICY.md`](./CRAWLER_POLICY.md)

- 遵守 robots.txt 與網站使用條款。  
- 每次請求間隔 1~3 秒，避免高頻率訪問。  
- 僅擷取公開資料（不登入、不模擬使用者）。  
- 標註資料來源：
  ```
  資料來源：104 人力銀行（https://www.104.com.tw/），僅供教育與非商業研究用途。
  ```
- 不收集個資、不散布職缺明細。  
- 若官方有疑慮，可立即聯繫修正：  
  📧 research@vibecoding.dev

---

## 🧩 專案架構

```
.
├── fetch-all.sh          # 主爬蟲腳本
├── CRAWLER_POLICY.md     # 安全與合規策略
├── requirements.txt      # Python 套件需求
├── examples/             # 範例輸出與報表
└── README.md             # 專案說明文件
```

---

## 📈 延伸應用

- 技能熱力圖（Heatmap）  
- 職缺薪資分布統計  
- 技能組合關聯圖 (Co-occurrence Graph)  
- 年度趨勢追蹤（透過 cronjob 週期爬取）

---

## 📜 授權條款

本專案以 [MIT License](LICENSE) 授權。  
禁止用於商業販售或重製 104 職缺內容。
