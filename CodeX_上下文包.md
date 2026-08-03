# CodeX 协作上下文包（WorkBuddy 经验迁移）

> **用途**：把 WorkBuddy 在美菜小B风控工作中积累的经验、规范、偏好一次性交给 CodeX，让两个 AI 助手能协同而不重复踩坑。
> **维护**：本文件由 WorkBuddy 生成/维护。每次更新后，把全文重新同步给 CodeX 的 memory 即可（详见文末「如何喂给 CodeX」）。
> **版本**：v1，2026-07-31 生成。

---

## 0. 协作定位（最重要，先读这段）

两个 AI 助手不是竞争关系，是**分工 + 接力**关系：

> **职责边界（常驻）**：WorkBuddy 掌握真实数据、业务判断和执行权；CodeX 掌握脱敏上下文中的 SQL 分析、代码生成和静态校验权。

| 角色 | 定位 | 擅长 | 环境限制 |
|------|------|------|----------|
| **WorkBuddy** | 本地 + 业务域大脑 | 守着你本机文件；SQL 规范与历史；Excel/Word/飞书技能；中文业务语境；跨会话记忆 | 本机曾仅 4GB 内存，大文件需流式处理 |
| **CodeX** | 通用编码专家 | 干净云端环境写独立脚本/工具/库；复杂重构；不受本地内存限制 | 无你本机文件、无业务记忆、不直连飞书 |

**接力方式（文件即契约）**：
1. WorkBuddy 写一份「任务规格」md 文件（需求 + 数据样例 + 约束 + 验收标准）
2. CodeX 读规格，产出代码/脚本
3. WorkBuddy 把代码拿回本机验证、跑通、交付
4. CodeX 产出的可复用成果，回流进 WorkBuddy 的 skills / memory

**单一事实源**：SQL 规范与业务规则以本包 + 仓库内的 `LinkStar_SQL字典_CodeX版.md` 为准，两边保持一致，改一处就同步另一处。

### 常驻硬规则（每次任务默认携带）

1. 真实数据、生产库连接、凭证和最终执行权只留在 WorkBuddy；给 CodeX 的内容必须脱敏、最小化。
2. CodeX 只基于脱敏上下文做 SQL 分析、代码生成和静态校验，不宣称已经执行或验证生产 SQL。
3. SQL 首行不写注释；非测试库禁止 `CREATE`、`ALTER`、`DROP` 等 DDL。
4. 分区表必须在 `WHERE` 中写分区条件；不能只写在 `ON` 中。先确认分区字段是 `dt` 还是 `datekey`。
5. `ods.ods_company_store_t_receiver` 在 `LEFT JOIN` 子查询中不能使用 `dt` 过滤。
6. `customer_center.customer_figure` 不能单独 `FROM`，必须通过 `LEFT JOIN` 使用，并用业务日期字段过滤。
7. 大表必须缩小时间范围；订单明细、运单明细等场景按需使用 `ROW_NUMBER`、`LIMIT`，避免全量扫描。
8. 销售工号排除 `HS` 开头的记录。
9. 中文字段别名使用反引号；状态值优先用 `CASE` 解码为中文。
10. 已确认正确的 SQL 逻辑不擅自改动；优先给出原因、最小补丁和待验证假设。
11. SQL 修复必须经过 WorkBuddy 本地执行验证；CodeX 根据实际报错继续迭代。
12. 涉及具体表字段时只加载相关字典片段，不默认携带整份上下文包。

---

## 1. 用户与业务背景

- **用户**：路安之，美菜（B2B 食材供应链企业）**小B风控稽查数据分析师**，入职约 3 个月（2026 年）。
- **工作链路**：识别 → 稽查 → 处置 → 公示。
- **日常**：违规稽查、多维数据分析（门店/销售/订单/人力）、策略验证、商户调研、处罚通报。
- **主平台**：LinkStar（Doris 数仓）写 SQL；飞书文档出周报/通报。
- **系统**：Windows + Git Bash，用户名 `MC`。沟通语言：**中文**。

---

## 2. SQL 规范（LinkStar / Doris）—— 最高频踩坑区

> 完整字段字典与更多踩坑案例见同仓库的 **`LinkStar_SQL字典_CodeX版.md`**（已去除本地路径依赖，CodeX 直接 `cat` 或粘贴即可）。本包第 2 节是高频规则节选，写 SQL 前必读；涉及具体表字段时再查字典。

### 2.1 硬性平台规范（写任何 SQL 前必守）
- **首行无注释**。
- **非测试库禁止 DDL**（CREATE/ALTER/DROP 等）。
- `customer_center.customer_figure` **不能单独 FROM 查询**，必须 LEFT JOIN 绕过 DDL 检查。
- 分区表 **WHERE 必须带 dt 条件**；分区条件**只能写在 WHERE 里**，写在 ON 里会被 Hive 严格模式拒绝（用子查询包裹）。
- 销售工号 **排除 `HS` 开头**记录。
- 字段中文别名用**反引号**包裹（`` `门店id` ``）。
- 状态值用 **CASE 解码为中文**（0→否，1→是）。

### 2.2 必须加分区条件的表（节选关键）
| 表 | 分区字段 | 注意 |
|----|----------|------|
| `dws.dws_perf_company_peroid_detail_merge` | `dt` INT | CTE 锚点表 |
| `dwd.dwd_ord_order_item_detail` | `dt` **STRING** | 数据量极大，必须 ROW_NUMBER 去重 |
| `dim.dim_cangchu_warehouse_ext` | **`datekey`**（非 dt）INT | 字段名是 datekey |
| `app.app_crm_bd_company_relation` | `dt` STRING | 常用 `WHERE dt = (SELECT MAX(dt) ...)` |
| `price_stg_app.driver_sale_service_item_1h` | `dt` INT | 销售服务主单明细，含 GMV/佣金全量字段 |
| `ods.ods_crm_db_company_visit_v4` | `dt` INT | BD 拜访记录 v4，57 字段 |
| `dwd.dwd_tms_waybill_item_detail` | `dt` INT | 运单明细，90+ 字段，极易 OOM |

### 2.3 高风险特例（必错点）
- `ods.ods_company_store_t_receiver`（门店子账号主档）：**LEFT JOIN 子查询中不能用 dt 过滤**，否则 `Unknown column 'dt' in 'table list'`；CTE 中 FROM 可不加 dt。
- `customer_center.customer_figure`：用 `company_create_time` / `last_order_time`（整数 yyyyMMdd）过滤，不能单独 FROM。
- `data_svip.company_store_t_unit`：无分区，主键是 `id` 不是 `company_id`。

### 2.4 常用表速记
- `customer_center.customer_figure`（门店画像主表）
- `app.app_crm_bd_company_relation`（销售-门店归属）
- `dwd.dwd_crm_org_user_relation_info`（在职：`is_deleted=0 AND auth_status=1`）
- `corp.t_company_change_log`
- `ods.ods_pay_core_t_pay_core_order`
- `ods.ods_company_store_t_receiver`（门店子账号主档）
- `dws.dws_perf_company_peroid_incre_rec_detail`（增量佣金）
- `dws.dws_perf_company_peroid_stock_rec_detail_v2`（存量佣金）
- 多 CTE + 临时表（如 `externaldb.lu_qizha0720`）做批量门店/company_id 分析。

---

## 3. 核心项目规则

- **店铺重复注册检测**：open_id 一致性 + SKU 重合度。A、B 两店若**支付账户 + 手机号均相同** = 匹配。分析时间窗 `20260616-20260706`。输出 SQL 须脱敏：`concat(company_name,'-删除')`；排除名称含 `-删除` 后缀及「家庭/个人」记录。
- **SKU 重复注册策略** v1–v8；门店重复率匹配规则。
- **小B周报**（业务违规行为风控周报_小B）+ 月度处罚通报。飞书文档：`https://meicai.feishu.cn/docx/AaKwdeAfGouY7exo0UVcdmsinsd`。

---

## 4. 输出与协作偏好（直接影响成品质量）

- **回复风格「简单写」**：加粗标题 + 概括 + 展开，3~4 点精炼；带可运行 SQL 代码块 + 结构化对比表。
- **迭代式调试**：逐步加字段/条件 → 运行 → 修复 → 确认；遇错提供日志求修复，**不改已正确的逻辑**；重写前先搜历史对话和已有 `.sql` 文件。
- **Word 文档**：干净无 markdown、无乱码、彩色高亮。
- **Excel**：严格保持原格式（列名/列数/颜色/合并单元格），输出前对照参考验证。
- **分步执行**：每步完成才推进下一步；操作前提供备份文件、命令明确目标路径；以**硬证据**（文件/目录检查）确认后才宣告成功；写飞书前先确认草稿。
- **备份整洁**：仅工作文件 + 1 个明确改名的安全备份，不堆时间戳快照。
- 熟悉**华为流程管理法六大模块**，规划要体现闭环思维。

---

## 5. Excel / xlsx 处理规范（给 CodeX 写处理脚本时必看）

- **数字格式**：纯数字文本（如 `'0153525`）转真数字、去前导零；例外：**8 位且 19/20 开头**（如 `20251231`）视为日期文本保留，不转数字。
- **大文件流式处理**：旧机 4GB 内存、`openpyxl read_only=True` 对 WPS 保存的 xlsx 失效（只读 1 行）→ 用 `zipfile + xml.etree.ElementTree.iterparse` 流式解析（sharedStrings 全载 + 逐 row 取 cell）。**新机内存放宽，但流式仍推荐**。
- **禁忌**：绝不用正则/字符串替换改 xlsx 内部 XML（会写坏，openpyxl 报 `mismatched tag`）；所有改动走 openpyxl API（`ws.cell.value=`、`del row_dimensions[r]`）。
- WPS xlsx 常遗留空 row 桩 → `del ws.row_dimensions[r]`（r>数据末行）后 save。
- 文件被 WPS/Excel 打开时写回会 `PermissionError` → 另存新文件，提示用户关闭原文件。
- 改完大文件用 openpyxl 重新 load 验证能打开（防静默损坏）再交付。

---

## 6. WorkBuddy 已具备的能力（CodeX 不必重造）

以下能力 WorkBuddy 已有现成 skill，**需要这类产出时直接交给 WorkBuddy，别在云端从零写**：

| Skill | 能力 | 何时交给 WorkBuddy |
|-------|------|--------------------|
| `low-memory-xlsx` | 4GB 机器流式读写大 xlsx | 任何 Excel 批处理 |
| `generate-xiaob-weekly-report` | 自动生成小B风控周报 → 飞书 | 周报/通报产出 |
| `penalty-long-image` | Word 转长图（WPS COM + pypdfium2） | 处罚通报转图片 |
| `tencentcloud-ocr` | 腾讯云高精度 OCR | 图片/截图提取文字 |
| `find-salesperson` | 按姓名查销售/员工信息 | 查销售归属 |
| `honor-poster` | 荣誉表彰海报生成 + 飞书私发 | 表彰场景 |
| `yunshan-create-skill` / `yunshan-create-static-lightapp` | 云杉 Skill / 静态轻应用脚手架 | 轻应用开发 |
| `openclaw-feishu-docs-perm-auto` | 飞书文档自动加权限 | 飞书文档协作 |

---

## 7. 给 CodeX 的协作约定

1. **分工**：WorkBuddy 掌握真实数据、业务判断和执行权；CodeX 掌握脱敏上下文中的 SQL 分析、代码生成和静态校验权。生产库连接和生产数据查询不交给 CodeX。
2. **交接文件格式**：WorkBuddy 用仓库内的 `任务规格模板.md` 填写「目标 / 输入数据样例（脱敏）/ 约束（含本包第 2、5 节规范）/ 验收标准」后交给 CodeX。CodeX 产出代码时，**代码注释与变量名用中文**，并附一段「如何使用 + 如何在 WorkBuddy 本机运行」的说明。
3. **SQL 相关**：CodeX 若写 SQL，必须严格遵守本包的常驻硬规则和第 2 节；涉及具体表时只提供相关字段字典和最小脱敏样例。
4. **数据安全**：给 CodeX 的样例数据必须脱敏、最小化；优先使用虚构 ID 和扰动后的值，不要把生产库凭证、真实商户隐私或完整结果集交给云端。
5. **经验回流**：CodeX 写出的可复用脚本，WorkBuddy 会纳入 skills 或 memory；改了本包任何规则，两边同步更新。

---

## 协作仓库文件清单（已准备好，等推远程）

本协作内容已放在一个独立 Git 仓库骨架里（`C:\Users\MC\WorkBuddy\协作\`，已 `git init` 并首次提交）。仓库内文件：

| 文件 | 内容 | CodeX 怎么用 |
|------|------|--------------|
| `CodeX_上下文包.md` | 协作定位、用户背景、SQL 高频规范、项目规则、输出偏好、Excel 规范、skill 清单、协作约定 | 进 Codex memory，或开工前 `cat` |
| `LinkStar_SQL字典_CodeX版.md` | 完整分区表规则 + 字段字典（去本地路径） | 写 SQL 时 `cat` 查具体表字段 |
| `任务规格模板.md` | WorkBuddy → CodeX 的标准交接文件骨架（目标/脱敏样例/约束/验收） | 每次交给 CodeX 前复制填写 |

推远程步骤（等你装好 CodeX、建好空 GitHub 仓库后执行）：
```bash
cd C:/Users/MC/WorkBuddy/协作
git remote add origin <你的仓库URL>
git branch -M main
git push -u origin main
```
之后 WorkBuddy 这边更新了规范：`git add -A && git commit -m "同步规范" && git push`。

---

## 如何把本包喂给 CodeX（3 种方式，按推荐顺序）

1. **CodeX Memory（最省事，推荐）**：CodeX 有 memory/自定义指令功能。把 `CodeX_上下文包.md` 全文粘贴进 Codex 的 memory，它之后每次会话自动带上这份上下文。更新后重贴一次即可。
2. **共享 Git 仓库（最稳，适合长期）**：上文仓库推到 GitHub 后，CodeX 开工前 `cat CodeX_上下文包.md LinkStar_SQL字典_CodeX版.md` 即可获得完整规范；WorkBuddy 这边改了推同一仓库，两边永远同步。
3. **每次任务粘贴相关段落**：不想配 memory，就在给 CodeX 的 prompt 里贴对应小节（如让它写 SQL 就贴第 2 节 + 字典，写 Excel 脚本就贴第 5 节）。

> ⚠️ 注意：CodeX 是云端环境，**读不到你 C 盘本地文件**。本包第 1、6 节提到的本地路径（如 `C:\Users\MC\WorkBuddy\...`）仅供你/WorkBuddy 定位，给 CodeX 用时请以仓库内的 `LinkStar_SQL字典_CodeX版.md` 为准（已去除本地路径）。
