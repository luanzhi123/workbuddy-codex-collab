# 任务规格：门店B下单频次高检查（在现有重复注册检测SQL上增量优化）

> **协作类型**：WorkBuddy → CodeX 交接契约（CodeX 只做 SQL 静态分析与改写，不执行生产 SQL）
> **基线**：下方第 2 节的 SQL 是**已在 LinkStar/Doris 验证可运行**的版本，本次只增量添加，不改动任何已正确的逻辑与列。

---

## 0. 一句话目标
在现有「门店重复注册检测」SQL 中，新增一个**门店B（second_company_id）近30天下单频次**的检查列：若近30天下单次数 > 10，则该列显示「是」，否则「否」。

---

## 1. 背景与上下文
- 业务：小B风控——识别疑似重复注册/作弊的门店对（A、B 两店）。
- 现有 SQL 已产出：共用支付id个数、一致支付id使用次数、弱信号判定、门店距离、地址修改后订单情况、销售归属等。
- 本次仅为**增量增强**：原逻辑、原列、原筛选条件一律不动。

---

## 2. 输入数据 / 现有 SQL（基线，需保留结构）

**说明**：以下为待优化的完整 SQL（已验证可运行）。本任务只在其基础上「加一个 CTE + 一个 LEFT JOIN + 一个 SELECT 列」，其余逐字保留。

```sql
store_open_id as (
  select cast(agent_user_id as bigint) as company_id, open_id
  from ods.ods_pay_core_t_pay_core_order
  where dt between 20250701 and 20260719
    and open_id != ''
    and pay_amount > 0
    and pay_status in (2, 10)
    and agent_user_id is not null
    and agent_user_id != ''
    and agent_user_id regexp '^[0-9]+$'
  group by cast(agent_user_id as bigint), open_id
),

ab_pair_intersect as (
  select a.company_id as first_company_id,
         b.company_id as second_company_id,
         count(*) as same_open_id_cnt,
         sum(least(a.pay_cnt, b.pay_cnt)) as sum_least_pay
  from (
    select cast(agent_user_id as bigint) as company_id, open_id, count(*) as pay_cnt
    from ods.ods_pay_core_t_pay_core_order
    where dt between 20250701 and 20260719
      and open_id != ''
      and pay_amount > 0
      and pay_status in (2, 10)
      and agent_user_id is not null
      and agent_user_id != ''
      and agent_user_id regexp '^[0-9]+$'
    group by cast(agent_user_id as bigint), open_id
  ) a
  join (
    select cast(agent_user_id as bigint) as company_id, open_id, count(*) as pay_cnt
    from ods.ods_pay_core_t_pay_core_order
    where dt between 20250701 and 20260719
      and open_id != ''
      and pay_amount > 0
      and pay_status in (2, 10)
      and agent_user_id is not null
      and agent_user_id != ''
      and agent_user_id regexp '^[0-9]+$'
    group by cast(agent_user_id as bigint), open_id
  ) b on a.open_id = b.open_id and a.company_id > b.company_id
  group by a.company_id, b.company_id
),

ab_intersect_same_day as (
  select a.company_id as first_company_id, b.company_id as second_company_id, a.open_id, a.dt
  from (
    select cast(agent_user_id as bigint) as company_id, open_id, dt
    from ods.ods_pay_core_t_pay_core_order
    where dt between 20250701 and 20260719
      and open_id != ''
      and pay_amount > 0
      and pay_status in (2, 10)
      and agent_user_id is not null
      and agent_user_id != ''
      and agent_user_id regexp '^[0-9]+$'
    group by cast(agent_user_id as bigint), open_id, dt
  ) a
  join (
    select cast(agent_user_id as bigint) as company_id, open_id, dt
    from ods.ods_pay_core_t_pay_core_order
    where dt between 20250701 and 20260719
      and open_id != ''
      and pay_amount > 0
      and pay_status in (2, 10)
      and agent_user_id is not null
      and agent_user_id != ''
      and agent_user_id regexp '^[0-9]+$'
    group by cast(agent_user_id as bigint), open_id, dt
  ) b on a.open_id = b.open_id and a.dt = b.dt and a.company_id > b.company_id
  group by a.company_id, b.company_id, a.open_id, a.dt
),

ab_same_day_cnt as (
  select first_company_id, second_company_id, count(distinct dt) as same_open_id_same_day_cnt
  from ab_intersect_same_day
  group by first_company_id, second_company_id
),

company_last_order_after_move as (
  select orders.company_id as company_id,
         max(case when orders.dt > changes.address_change_date then orders.dt end) as last_order_after_move
  from (
    select cast(agent_user_id as bigint) as company_id, dt
    from ods.ods_pay_core_t_pay_core_order
    where dt between 20250701 and 20260719
      and pay_amount > 0
      and pay_status in (2, 10)
      and agent_user_id is not null
      and agent_user_id != ''
      and agent_user_id regexp '^[0-9]+$'
    group by cast(agent_user_id as bigint), dt
  ) orders
  left join (
    select company_id, from_unixtime(c_t, '%Y%m%d') as address_change_date
    from corp.t_company_change_log
    where json_extract(old_fields, '$.area_id') != json_extract(new_fields, '$.area_id')
      and json_extract(old_fields, '$.area_id') is not null
      and json_extract(new_fields, '$.area_id') is not null
      and cast(json_extract(old_fields, '$.area_id') as int) != 0
      and from_unixtime(c_t, '%Y%m%d') between 20260701 and 20260719
  ) changes on orders.company_id = changes.company_id
  group by orders.company_id
)

select distinct
  t.first_company_id as `门店A_id`,
  concat(a1.company_name, '-删除') as `门店A_名称`,
  dc1.daqu as `门店A_大区`,
  a1.city_name as `门店A_城市`,
  case c1.manage_type when 100 then '小B' when 200 then '中B' end as `业务线`,
  case a1.status when 1 then '有效' when -1 then '无效' when -3 then '停用' else '其他' end as `门店A_门店状态`,
  a1.company_create_time as `门店A_注册日期`,
  a1.last_order_time as `门店A_末单时间`,
  t.second_company_id as `门店B_id`,
  concat(a2.company_name, '-删除') as `门店B_名称`,
  dc2.daqu as `门店B_大区`,
  a2.city_name as `门店B_城市`,
  a2.company_create_time as `门店B_注册日期`,
  a2.last_order_time as `门店B_末单时间`,
  t.same_open_id_cnt as `共用支付id个数`,
  t.sum_least_pay as `一致支付id使用次数`,
  case when t.sum_least_pay < 3 then '弱信号' else '强信号' end as `是否弱信号_小于3次`,
  round(6378137 * 2 * asin(sqrt(
      power(sin((cast(latlng1.lat as double) - cast(latlng2.lat as double)) * 3.141592653589793 / 360), 2)
    + cos(cast(latlng1.lat as double) * 3.141592653589793 / 180)
      * cos(cast(latlng2.lat as double) * 3.141592653589793 / 180)
      * power(sin((cast(latlng1.lng as double) - cast(latlng2.lng as double)) * 3.141592653589793 / 360), 2)
  )), 2) as `门店距离(米)`,
  if(d2.address_change_date is null, '', d2.address_change_date) as `门店B_地址修改日期`,
  case
    when d2.address_change_date is not null and cloa.last_order_after_move is null then '修改地址后无订单'
    when d2.address_change_date is not null and cloa.last_order_after_move is not null then concat('修改地址后仍有订单，末单时间:', cloa.last_order_after_move)
    else '未修改地址'
  end as `地址修改后订单情况`,
  corp1.address as `门店A_地址`,
  corp1.phone as `门店A_电话`,
  corp2.address as `门店B_地址`,
  corp2.phone as `门店B_电话`,
  org_info.user_id as `销售id`,
  org_info.sale_code as `员工编号`,
  org_info.user_name as `销售姓名`
from ab_pair_intersect t
left join ab_same_day_cnt ad on ad.first_company_id = t.first_company_id and ad.second_company_id = t.second_company_id
left join customer_center.customer_figure a1 on a1.company_id = t.first_company_id
left join customer_center.customer_figure a2 on a2.company_id = t.second_company_id
left join externaldb.sgh_city_area_202607 dc1 on dc1.city_id = a1.city_id
left join externaldb.sgh_city_area_202607 dc2 on dc2.city_id = a2.city_id
left join dim.dim_company_basic_info latlng1 on latlng1.company_id = t.first_company_id
left join dim.dim_company_basic_info latlng2 on latlng2.company_id = t.second_company_id
left join data_svip.company_store_t_unit corp1 on corp1.id = t.first_company_id
left join data_svip.company_store_t_unit corp2 on corp2.id = t.second_company_id
left join dws.dws_company_type_info c1 on c1.company_id = t.first_company_id and c1.dt = date_sub(current_date(), 1)
left join (
  select company_id, from_unixtime(c_t, '%Y%m%d') as address_change_date,
         row_number() over(partition by company_id order by c_t desc) as rn
  from corp.t_company_change_log
  where json_extract(old_fields, '$.area_id') != json_extract(new_fields, '$.area_id')
    and json_extract(old_fields, '$.area_id') is not null
    and json_extract(new_fields, '$.area_id') is not null
    and cast(json_extract(old_fields, '$.area_id') as int) != 0
    and from_unixtime(c_t, '%Y%m%d') between 20260701 and 20260719
) d2 on d2.company_id = t.second_company_id and d2.rn = 1
left join company_last_order_after_move cloa on cloa.company_id = t.second_company_id
left join (
  select company_id, op_id, op_name, result_description, from_unixtime(c_t, '%Y-%m-%d') as dt from (
    select unit_id as company_id, op_id, op_name, c_t, result_description,
           row_number() over(partition by very.unit_id order by very.u_t desc) as veryorder
    from ods.ods_t_unit_pre_verify very
    join customer_center.customer_figure a1 on a1.company_id = very.unit_id
  ) ver where ver.veryorder = 1
) bd on bd.company_id = t.first_company_id
left join dwd.dwd_crm_org_user_relation_info org_info on org_info.dt = bd.dt and org_info.position_id = bd.op_id and org_info.dt <= date_sub(current_date(), 1)
where a1.company_create_time >= 20260701
  and dc1.daqu is not null
  and dc2.daqu is not null
  and org_info.user_id is not null
  and a1.company_name not like '%家庭/个人%'
  and a2.company_name not like '%家庭/个人%'
  and (
    round(6378137 * 2 * asin(sqrt(
        power(sin((cast(latlng1.lat as double) - cast(latlng2.lat as double)) * 3.141592653589793 / 360), 2)
      + cos(cast(latlng1.lat as double) * 3.141592653589793 / 180)
        * cos(cast(latlng2.lat as double) * 3.141592653589793 / 180)
        * power(sin((cast(latlng1.lng as double) - cast(latlng2.lng as double)) * 3.141592653589793 / 360), 2)
    )), 2) < 1000
    or (
      round(6378137 * 2 * asin(sqrt(
          power(sin((cast(latlng1.lat as double) - cast(latlng2.lat as double)) * 3.141592653589793 / 360), 2)
        + cos(cast(latlng1.lat as double) * 3.141592653589793 / 180)
          * cos(cast(latlng2.lat as double) * 3.141592653589793 / 180)
          * power(sin((cast(latlng1.lng as double) - cast(latlng2.lng as double)) * 3.141592653589793 / 360), 2)
      )), 2) > 1000
      and d2.address_change_date is not null
      and cloa.last_order_after_move is null
    )
  );
```

---

## 3. 要产出的东西（交付物）
- **交付物 1**：一份**完整可运行**的 SQL（在上方基线之上增量修改），包含：
  1. 一个新的 CTE，例如 `b_store_order_freq`，按 `company_id` 聚合计算**门店B近30天下单次数**（口径见第 6 节）；
  2. 主查询中新增一个 `LEFT JOIN b_store_order_freq bf on bf.company_id = t.second_company_id`；
  3. 主查询 `SELECT` 列表新增一列：`case when bf.b_order_cnt_30d > 10 then '是' else '否' end as \`B门店下单频次高\``，位置放在门店B相关列附近即可。
- **交付物 2**：一段简短说明——新 CTE 的逻辑、近30天口径取值、以及「为什么这样判定频次高」。
- **必须**：输出**完整 SQL**（不要只给 diff 片段），WorkBuddy 要直接拿去 LinkStar 跑。

---

## 4. 约束（必守，勾选）
- [x] 遵守 `CodeX_上下文包.md` 的「常驻硬规则」与第 2 节 SQL 规范
- [x] **首行不写注释**；非测试库**禁 DDL**
- [x] 分区表 `ods.ods_pay_core_t_pay_core_order` 的 CTE/子查询 **WHERE 必须带 `dt` 条件**（新 CTE 也须带，如 `dt between 20260619 and 20260719`）
- [x] `customer_center.customer_figure` 保持**原有 LEFT JOIN 用法**，不得改为单独 FROM
- [x] 中文字段别名用**反引号**包裹（`` `B门店下单频次高` ``）
- [x] 状态值用 **CASE 解码为中文**（是/否）
- [x] **不擅自改动任何已正确的逻辑/列/筛选条件**；只做新增（加 CTE + JOIN + 列）
- [x] 代码注释与变量名用**中文**
- [x] 不宣称已执行/验证生产 SQL（只做静态改写）
- [x] 其它：保持原 SQL 的表别名与缩进风格一致

---

## 5. 验收标准（WorkBuddy 拿回本机后逐条核对）
- [ ] 新 SQL 在 LinkStar 能正常提交、无语法/Hive 严格模式报错
- [ ] 新增列 `B门店下单频次高` 出现在结果中，取值仅「是」/「否」
- [ ] 频次判定：近30天下单次数 **> 10** 显示「是」，否则「否」
- [ ] 原 SQL 的所有列、筛选条件、逻辑**完全不变**（diff 仅多出新 CTE + 1 个 LEFT JOIN + 1 个 SELECT 列）
- [ ] 新 CTE 对 `ods.ods_pay_core_t_pay_core_order` 带 `dt` 分区条件、带与基线一致的 `pay_amount>0 / pay_status in (2,10) / agent_user_id` 过滤
- [ ] 解释说明清晰：近30天口径、阈值含义

---

## 6. 交接备注 / 待确认点
- **「近30天」口径（重要）**：基线数据窗口为 `dt between 20250701 and 20260719`。本规格默认「近30天」= 分析窗口末日 `20260719` 往前推 30 天，即 `dt between 20260619 and 20260719`。若你有别的口径（如相对 `current_date`），请在产出时说明所用口径。
- **阈值**：「超过10频」按 **严格大于 10**（即 `> 10`）理解；如应为 ≥10 请注明。
- **频次计数口径**：默认只统计 `pay_amount > 0 and pay_status in (2,10)` 的有效订单（与基线 order 过滤一致），按 `company_id = second_company_id`（即门店B）聚合 `count(*)`。
- **已知风险**：原 SQL 尾部的 `));` 是既有结构，请原样保留，不要因新增 CTE 而破坏外层括号配对。
- **回传方式**：把完整 SQL + 说明贴在回复里（或写入本仓库同名 `.sql` 文件由 WorkBuddy 拉取）。

---

_本规格由 WorkBuddy 按 `任务规格模板.md` 填写，2026-08-03。_

---

## 7. 交付验收（WorkBuddy 复核，2026-08-03）

CodeX 已返回完整 SQL（见同目录 `门店B下单频次检查_优化版.sql`）。逐项核对验收标准：

| 验收项 | 结果 |
|--------|------|
| 新增列 `B门店下单频次高`，取值仅「是/否」 | ✅ `case when bf.b_order_cnt_30d > 10 then '是' else '否' end` |
| 阈值逻辑：> 10 显示「是」 | ✅ `bf.b_order_cnt_30d > 10` |
| 仅增量新增（新 CTE + 1 LEFT JOIN + 1 列），原逻辑/列/筛选未动 | ✅ diff 干净 |
| 新 CTE 对 `ods_pay_core_t_pay_core_order` 带 `dt` 分区条件 | ✅ `dt between 20260619 and 20260719` |
| 新 CTE 带与基线一致的 `pay_amount>0 / pay_status in (2,10) / agent_user_id` 过滤 | ✅ |
| customer_figure 保持 LEFT JOIN | ✅ 未改动 |
| 中文别名反引号 + CASE 解码 | ✅ |
| 尾部 `));` 结构保留 | ✅ |

**判定：全部通过，可交付运行。**

### 口径说明（CodeX 未附文字说明，由 WorkBuddy 补充）
- **近30天**：采用规格默认口径 = 分析窗口末日 `20260719` 往前推 30 天 → `dt between 20260619 and 20260719`。注意这是**固定窗口**，不会随运行日期滚动；若需「相对当前日期」的滚动口径，应改为 `dt >= date_sub(current_date(), 30)`（需同步评估全量扫描风险）。
- **频次计数**：对门店B（`second_company_id`）在窗口内的有效订单（同基线过滤）按 `company_id` 聚合 `count(*)`。
- **NULL 处理**：LEFT JOIN 下若门店B在窗口内无订单，`b_order_cnt_30d` 为 NULL → 判「否」，符合需求（仅 >10 才「是」）。

### 运行提示
- 本文件 CTE 块以 `store_open_id as (` 开头，**运行前需在最前面补 `with`**（与你原版一致）。
- 我（WorkBuddy）无生产库执行权限，仅做静态复核；请在 LinkStar 实际跑一遍确认。

