# LinkStar 分区规则速查表（CodeX 云端版）

> **适用**：本文件是给 CodeX（云端环境）使用的独立副本，不依赖任何本地路径，可直接 `cat` 或粘贴使用。
> **来源**：由 WorkBuddy 本机 `美菜-SQL代码/LinkStar_分区规则速查.md` 同步而来，与 `CodeX_上下文包.md` 配套。
> **同步**：WorkBuddy 本机字典更新后，重新拷贝本文件即可。
> 编写SQL时参考此表，避免 Hive严格模式报错和内存超限问题。
> 最后更新：2026-05-13（经实战验证）

---

## 一、必须加分区条件的表（Hive 严格模式）

以下表在 **WHERE 子句** 中必须加分区过滤，否则报 `Queries against partitioned tables without a partition filter are disabled`。

> ⚠️ **关键规则**：分区条件必须写在 **WHERE** 里！只写在 **ON 条件** 中会被 Hive 拒绝。解决办法：用子查询包裹，在子查询的 WHERE 里加分区。

| # | 表名 | 分区字段 | 字段类型 | 常用写法 | 特殊注意 |
|---|---|---|---|---|---|
| 1 | `dws.dws_perf_company_peroid_detail_merge` | `dt` | INT | `WHERE dt BETWEEN 20260211 AND 20260511` | **CTE锚点表**，通常作为第一个CTE的数据源 |
| 2 | `dws.dws_company_type_info` | `dt` | INT | `AND type_a.dt = DATE_SUB(CURRENT_DATE(), 1)` | 业务线(小B/中B)，JOIN时用T-1 |
| 3 | `dwd.dwd_crm_org_user_relation_info` | `dt` | INT/STRING | `AND org_info.dt = audit.verify_dt` | 销售组织架构，用审核日期关联 |
| 4 | `dwd.dwd_ord_order_item_detail` | `dt` | **STRING** | `WHERE dt BETWEEN 20250501 AND 20260513` | ⚠️ 数据量极大！需用 ROW_NUMBER 去重 |
| 5 | `dim.dim_cangchu_warehouse_ext` | **`datekey`**（非dt） | INT | `WHERE datekey >= 20250501` | 注意字段名是 **datekey** 不是 dt |
| 6 | `ods.ods_pay_collect` | `dt` | STRING | `WHERE dt = ...` | 支付流水 |
| 7 | `ods.ods_order_main` | `dt` | STRING | `WHERE dt = ...` | 订单主表（LinkStar无权限） |
| 8 | `ods.ods_order_detail` | `dt` | STRING | `WHERE dt = ...` | 订单明细（LinkStar无权限） |
| 9 | `app.app_crm_bd_company_relation` | `dt` | STRING | `WHERE dt = (SELECT MAX(dt) FROM app.app_crm_bd_company_relation)` | 销售-门店归属 |
| 10 | **`price_stg_app.driver_sale_service_item_1h`** | **`dt`** | **INT** | **WHERE dt >= 20260501** | **销售服务主单明细**（小时级/日级），含GMV/佣金/配送/客诉等全量字段 |
| 11 | **`ods.ods_crm_db_company_visit_v4`** | **`dt`** | **INT** | **WHERE dt >= 20260601** | **BD拜访记录表v4**，含拜访目的/结果/打点坐标/陪访人/联系人等57字段 |
| 12 | **`dwd.dwd_tms_waybill_item_detail`** | **`dt`** | **INT** | **WHERE dt >= 20250101** | **运单明细表（TMS）**，含配送全链路时间线/司机/站点/线路/商品等90+字段，数据量极大需加LIMIT或ROW_NUMBER |

### 🔴 高风险表（特殊限制）

| # | 表名 | 分区字段 | 限制说明 |
|---|---|---|---|
| ⭐A | `ods.ods_company_store_t_receiver` | `dt`(STRING) | **在LEFT JOIN子查询中不能使用dt做过滤！** 会报 `Unknown column 'dt' in 'table list' in FILTER clause`。CTE中FROM用可以不加dt条件。 |
| B | `ods.ods_t_unit_pre_verify` | 未确认 | 实战中不加dt条件也能跑通（与customer_figure JOIN时用customer_id关联即可） |
| C | `dim.dim_company_main_type_1d` | `dt`(INT) | 主营类型表，JOIN时用 `a.dt = dim.dt` |

---

## 二、不需要加分区条件的表

以下表无分区字段或不需要分区过滤，直接 JOIN 即可。

| # | 表名 | 说明 | 过滤方式 |
|---|---|---|---|
| 1 | `customer_center.customer_figure` | 门店画像主表 | 用 `company_create_time` 或 `last_order_time`（整数格式 yyyyMMdd）做范围过滤；⚠️ 不能单独 FROM 查询，必须 LEFT JOIN 绕过 DDL 检查 |
| 2 | `data_svip.company_store_t_unit` | 门店地址/电话/注册手机 | **无分区字段**，直接 JOIN；主键是 `id` 不是 `company_id` |
| 3 | `externaldb.sgh_city_area_YYYYMM` | 城市-大区映射 | 维度小表，按年份选表名（如 `_202604`），无需分区过滤 |
| 4 | `corp.t_passport_phone` | passport账号手机号 | 无需分区 |
| 5 | `bizlog.spr` | 原始业务日志 | `dt`(日分区)，但一般按范围查即可 |

---

## 三、实战踩坑案例

### 案例1：仓库表分区条件写在ON → 报错
```sql
-- ❌ 错误写法（Hive严格模式拒绝）
LEFT JOIN dim.dim_cangchu_warehouse_ext wh2
  ON oi.warehouse_id = wh2.warehouse_id AND wh2.datekey = oi.dt

-- ✅ 正确写法（子查询+WHERE）
LEFT JOIN (
  SELECT warehouse_id, warehouse_name
  FROM dim.dim_cangchu_warehouse_ext
  WHERE datekey >= 20250501        ← 必须在WHERE里
) wh2 ON oi.warehouse_id = wh2.warehouse_id
```

### 案例2：receiver在子查询中加dt → 报错
```sql
-- ❌ 错误写法（LEFT JOIN内嵌子查询中不能有dt）
LEFT JOIN (
  SELECT customer_id, name, phone
  FROM ods.ods_company_store_t_receiver
  WHERE dt >= 20251001 AND is_deleted=0    ← 这里会报Unknown column 'dt'
) rec_a ON ...

-- ✅ 正确写法（去掉dt，只用业务字段过滤）
LEFT JOIN (
  SELECT customer_id, name, phone
  FROM ods.ods_company_store_t_receiver
  WHERE is_deleted=0                      ← 只保留非分区条件
) rec_a ON ...
```

### 案例3：订单明细表全量扫描 → 内存超限
```sql
-- ❌ 错误写法（数据量太大，MEM_LIMIT_EXCEEDED）
FROM dwd.dwd_ord_order_item_detail WHERE dt >= 20260101   -- 半年数据

-- ✅ 正确写法（ROW_NUMBER去重+缩小日期窗口）
FROM (
  SELECT company_id, warehouse_id, dt,
    ROW_NUMBER() OVER(PARTITION BY company_id ORDER BY dt DESC) AS rn
  FROM dwd.dwd_ord_order_item_detail
  WHERE dt BETWEEN 20250501 AND 20260513     -- 缩小到12天
) oi WHERE oi.rn = 1                         -- 每店只取1条
```

---

## 四、快速决策流程图

```
要用某张表？
    │
    ├─ dws.* / dwd.* / dim.* / ods.* / app.*
    │   → 大概率需要分区条件 → 查上表确认字段名和类型
    │       │
    │       ├─ 是 receiver? → 子查询中不能用dt！去掉dt条件
    │       ├─ 是 cangchu_warehouse_ext? → 字段叫datekey不是dt
    │       ├─ 是 ord_order_item_detail? → 必须ROW_NUMBER去重防OOM
    │       └─ 其他 → 正常加 dt/datekey WHERE 条件
    │
    ├─ customer_center.customer_figure
    │   → 不需要分区，用company_create_time过滤；不能单独FROM查询
    │
    ├─ data_svip.*
    │   → 不需要分区，直接JOIN
    │
    └─ externaldb.sgh_city_area_*
        → 维度小表，不需要分区，注意年份后缀
```

---

## 五、表字段字典

### `price_stg_app.driver_sale_service_item_1h` — 销售服务主单明细

> 分区：`dt` (INT) | 数据源：price_stg_app | 颗粒度：主单级

| 字段名 | 类型 | 说明 |
|--------|------|------|
| `company_id` | INT | **商户ID** |
| `company_name` | STRING | 商户名称 |
| `manage_type` | INT | 业务类型：100=小B, 200=中B, 201=PC, 300=大B |
| `code` | STRING | 主单编号 |
| `f_status` | INT | 主单状态ID |
| `f_status_name` | STRING | 主单状态 |
| `s_status` | INT | 子单状态ID |
| `s_status_name` | STRING | 子单状态 |
| `type` | INT | 类型：1=新开, 2=复活 |
| `first_com_type_id` | INT | 首次进入时阶段ID |
| `first_com_type` | STRING | 首次进入时阶段 |
| `now_com_type_id` | INT | 当前阶段ID |
| `now_com_type` | STRING | 当前阶段 |
| `gmv` | DECIMAL(30,5) | 当日下单GMV |
| `hexin_gmv` | DECIMAL(30,5) | 当日下单菜肉新GMV |
| `sale_rate` | DECIMAL(30,5) | 销售分佣比例 |
| `driver_rate` | DECIMAL(30,5) | 司机分佣比例 |
| `sale_salary_money_predicted` | DECIMAL(30,5) | 销售预计佣金 |
| `sale_rebate_salary` | DECIMAL(30,5) | 销售已获得佣金 |
| `sale_rebate_salary_settled` | DECIMAL(30,5) | 销售已结算佣金 |
| `sale_rebate_salary_unsettled` | DECIMAL(30,5) | 销售待结算佣金 |
| `driver_salary_money_predicted` | DECIMAL(30,5) | 司机预计佣金 |
| `driver_rebate_salary` | DECIMAL(30,5) | 司机已获得佣金 |
| `driver_rebate_salary_settled` | DECIMAL(30,5) | 司机已结算佣金 |
| `driver_rebate_salary_unsettled` | DECIMAL(30,5) | 司机待结算佣金 |
| `saler_id` | INT | 销售ID |
| `saler_name` | STRING | 销售名称 |
| `position_id` | INT | 销售岗位ID |
| `b_monitor_no` | STRING | 班排长编号 |
| `b_monitor_name` | STRING | 班排长名称 |
| `big_area_id` | INT | 大区ID |
| `big_area_name` | STRING | 大区 |
| `city_id` | INT | 城市ID |
| `city_name` | STRING | 城市 |
| `warehouse_id` | INT | 仓ID |
| `warehouse_name` | STRING | 仓 |
| `station_region_id` | INT | 站区ID |
| `station_region_name` | STRING | 站区 |
| `delivery_area_id` | INT | 路区ID |
| `delivery_area_name` | STRING | 路区 |
| `sale_area_id` | INT | 售卖区ID |
| `sale_area_name` | STRING | 售卖区 |
| `driver_no` | STRING | 司机编号 |
| `driver_name` | STRING | 司机名称 |
| `ps_driver_name` | STRING | 当日配送司机 |
| `self_delivery` | INT | 是否自配送 |
| `expect_receive_time` | STRING | 期望送达时间 |
| `complete_contract_time` | STRING | 实际妥投时间 |
| `is_wandian` | INT | 是否晚点 |
| `reason_class3_name` | STRING | 当日客诉 |
| `ks_sku_id` | STRING | 当日客诉SKU |
| `is_add_wx` | INT | 是否添加企业微信 |
| `create_date` | INT | 创建日期 |
| `effective_date` | INT | 生效日期 |
| `close_date` | INT | 结束日期 |
| `dt` | INT | **分区字段** |

---

### `ods.ods_crm_db_company_visit_v4` — BD拜访记录表

> 分区：`dt` (INT, yyyymmdd) | 数据源：ods | 颗粒度：拜访记录级（v4版本，57个字段）

| 字段名 | 类型 | 说明 |
|--------|------|------|
| `id` | BIGINT | 主键ID |
| `company_id` | BIGINT | **商家ID（门店ID）** |
| `company_name` | STRING | 商户名称 |
| `company_ownership` | BIGINT | 门店公私海归属：1=自己私海, 2=公海, 3=他人私海 |
| `company_source` | BIGINT | 门店来源 |
| `company_images` | STRING | 门店图片（JSON） |
| `company_images_ext` | STRING | 图片信息扩展 |
| `bd_id` | BIGINT | **BD ID** |
| `bd_name` | STRING | BD姓名 |
| `position_id` | BIGINT | BD岗位ID |
| `org_id` | BIGINT | BD直属组织ID |
| `city_id` | BIGINT | 门店所属城市ID |
| `version` | BIGINT | 数据版本：1=自营, 2=卫星城 |
| `business` | STRING | 业务线 |
| `is_vip` | BIGINT | 是否VIP |
| `visit_way` | BIGINT | 拜访类别：1=上门, 2=电话 |
| `visit_purpose` | STRING | 拜访目的 |
| `visit_reason` | STRING | 拜访原因 |
| `visit_result` | BIGINT | 是否达成：0=否, 1=是 |
| `visit_status` | BIGINT | 拜访进店状态：1=未进店, 2=拜访中, 3=已离店 |
| `status` | BIGINT | 拜访记录是否有效：0=无效, 1=有效 |
| `is_first` | BIGINT | 是否第一次拜访：0=否, 1=是 |
| `is_deleted` | BIGINT | 是否删除：1=已删除 |
| `reach_time` | BIGINT | 到店打卡时间 |
| `off_time` | BIGINT | 离店打卡时间 |
| `visit_stay_time` | BIGINT | 拜访消耗时间（单位：秒） |
| `gis_status` | BIGINT | 到店是否打点：默认0=不打点 |
| `off_gis_status` | BIGINT | 离店是否打点：默认0=不打点 |
| `gis_location` | STRING | 到店坐标 |
| `gis_address` | STRING | 到店打点具体地址 |
| `off_gis_location` | STRING | 离店坐标 |
| `off_gis_address` | STRING | 离店打点具体地址 |
| `distance` | DECIMAL(30,6) | 拜访者距离商户距离 |
| `contact_id` | BIGINT | 联系人ID |
| `contact_name` | STRING | 联系人姓名 |
| `contact_phone` | STRING | 联系人电话 |
| `is_kp` | BIGINT | 是否关键人 |
| `accompany_id` | BIGINT | 陪访人ID |
| `acc_visit_id` | BIGINT | 陪访记录ID |
| `accompany_name` | STRING | 陪访人姓名 |
| `accompany_phone` | STRING | 陪访人电话 |
| `accompany_position_id` | BIGINT | 陪访人岗位ID |
| `accompany_role` | BIGINT | 陪访人角色 |
| `accompany_complete` | BIGINT | 陪访人是否已填写陪访记录 |
| `is_poi` | BIGINT | 是否协助开店 |
| `f_status` | INT | （预留/主单状态相关字段，v4中可能未启用） |
| `f_status_name` | STRING | （预留） |
| `record_source` | BIGINT | 拜访记录添加来源：系统/自定义 |
| `record` | STRING | 拜访菜单内容和选定菜单（JSON） |
| `comment` | STRING | 额外信息（如放弃原因） |
| `date_key` | BIGINT | 拜访日期（格式：20180101） |
| `create_date` / `c_t` | BIGINT | 创建时间 |
| `u_t` | BIGINT | 修改时间 |
| `ts` | STRING | 数据写入时间 |
| `dt` | INT | **分区字段**（yyyymmdd） |

---

### `data_svip.company_store_t_unit` — 业务单元详情表

> 分区：**无分区字段** | 数据源：data_svip | 颗粒度：业务单元级（14个字段）
> ⚠️ **主键是 `id`**，不是 company_id！如需按门店ID查询，需通过其他表关联

| 字段名 | 类型 | 说明 |
|--------|------|------|
| `id` | BIGINT | **主键ID** |
| `name` | STRING | 名称 |
| `address` | STRING | 完整地址 |
| `address_detail` | STRING | 详细地址 |
| `poi_address` | STRING | POI地址 |
| `phone` | STRING | 负责人电话 |
| `lng` | STRING | 经度 |
| `lat` | STRING | 纬度 |
| `status` | BIGINT | 状态：0=待处理, 1=有效, -2=删除, -3=停用 |
| `is_deleted` | BIGINT | 是否删除 |
| `c_t` | BIGINT | 创建时间 |
| `u_t` | BIGINT | 更新时间(u_t) |
| `ts` | STRING | 数据写入时间 |

---

### `dwd.dwd_tms_waybill_item_detail` — 运单明细表（TMS配送）

> 分区：`dt` (INT, yyyymmdd) | 数据源：dwd | 颗粒度：运单明细级（每单每商品一行，**90+字段**）
> ⚠️ **数据量极大**！查询时必须加 `dt` 分区条件 + LIMIT / ROW_NUMBER，否则极易 OOM
> ⚠️ **无配送地址文本字段**，地址需 LEFT JOIN `data_svip.company_store_t_unit`

#### 一、订单主键

| 字段名 | 类型 | 说明 |
|--------|------|------|
| `company_id` | BIGINT | **客户ID（门店ID）** |
| `order_id` | BIGINT | 原始订单号 |
| `omc_order_id` | BIGINT | OMC订单ID |
| `order_item_id` | BIGINT | 原始订单明细ID（mall的订单号） |
| `omc_item_id` | BIGINT | OMC订单明细ID |
| `taskbill_no` | STRING | 任务单号 |
| `main_taskbill_no` | STRING | 主任务单号 |
| `waybill_no` | STRING | 运单号 |

#### 二、商品信息

| 字段名 | 类型 | 说明 |
|--------|------|------|
| `ssu_id` | BIGINT | SSU ID |
| `sku_id` | BIGINT | SKU ID |
| `ssu_name` | STRING | SSU名称（商品名称） |
| `class1_id` | BIGINT | 采销1级分类 |
| `class2_id` | BIGINT | 采销2级分类 |
| `class3_id` | BIGINT | 采销3级分类 |
| `is_standard` | BIGINT | 是否标品 |
| `activity_type` | BIGINT | 活动类型：0=普通, 1=满赠, 2=买赠, 3=促销, 4=秒杀 |
| `order_flag` | STRING | 2B/2C区分：2b=美菜, 2c=美鲜, mcdj=美菜到家 |
| `order_source` | BIGINT | 订单来源：0/99=美菜, 22/88/20/80=美鲜, 1=美菜到家, 10=外单 |

#### 三、数量与金额（20字段）

| 字段名 | 类型 | 说明 |
|--------|------|------|
| `expect_num` | DECIMAL(30,6) | 下单量（包裹件数） |
| `expect_weight` | DECIMAL(30,6) | 下称量（重量--计价量） |
| `shipment_num` | DECIMAL(30,6) | 发运数量 |
| `shipment_weight` | DECIMAL(30,6) | 发运重量 |
| `distribution_num` | DECIMAL(30,6) | 配送数量 |
| `distribution_weight` | DECIMAL(30,6) | 配送量（重量--计价量） |
| `return_weight` | DECIMAL(30,6) | 退货量（重量） |
| `adjustment_weight` | DECIMAL(30,6) | 调整后量（重量） |
| `replenishment_weight` | DECIMAL(30,6) | 补货量 |
| `replenishment_price` | DECIMAL(30,6) | 补货单价 |
| `real_price` | DECIMAL(30,6) | 优惠后单价（来源：商城） |
| `ord_real_price` | DECIMAL(30,6) | 优惠后单价（同real_price） |
| `amount_payable` | DECIMAL(30,6) | 应收总额 |
| `amount_receivable` | DECIMAL(30,6) | 实收总额 |
| `delivery_money` | DECIMAL(30,6) | 优惠后配送金额 |
| `delivery_unit_money` | DECIMAL(30,6) | 优惠前配送金额 |
| `delivery_notax_money` | DECIMAL(30,6) | 优惠后无税配送金额 |
| `online_pay_amount` | DECIMAL(30,6) | 在线支付金额 |
| `tax_rate` | DECIMAL(30,6) | 税率 |
| `pay_way` | STRING | 支付方式 |
| `pay_status` | BIGINT | 支付状态：0未收款, 10部分收款, 20司机收款, 30财务收款 |
| `amount_compense` | DECIMAL(30,6) | 赔偿金额 |
| `amount_arrears` | DECIMAL(30,6) | 欠款金额 |
| `amount_package` | DECIMAL(30,6) | 退包装物金额 |

#### 四、时间线（22字段）

| 字段名 | 类型 | 说明 |
|--------|------|------|
| `dt` | INT | **分区字段**（yyyymmdd） |
| `taskbill_date` | STRING | 创建日期 |
| `taskbill_time` | STRING | 创建时间 |
| `wiring_time` | BIGINT | 排线时间（时间戳） |
| `start_car_time` | BIGINT | 排车时间（时间戳） |
| `sort_time` | BIGINT | 分拣时间（时间戳） |
| `signin_time_arr` | BIGINT | 到仓签到时间（时间戳） |
| `distance_arr` | DECIMAL(30,6) | 到仓签到距离 |
| `signin_mode_arr` | BIGINT | 到仓签到方式：1扫码, 2自动, 3手动, 4调度代签 |
| `signin_time_leave` | BIGINT | 离仓签到时间（时间戳） |
| `distance_leave` | DECIMAL(30,6) | 离仓签到距离 |
| `signin_mode_leave` | BIGINT | 离仓签到方式：1扫码, 2自动, 3手动, 4调度代签 |
| `shipment_date` | STRING | 发运日期 |
| `shipment_time` | STRING | 发运时间 |
| `shipment_timestamp` | BIGINT | 发运时间（时间戳格式） |
| `receipt_time` | BIGINT | 司机接单时间 |
| `delivery_go_time` | BIGINT | 配送员出发时间（时间戳，在发运之后） |
| `delivery_time` | STRING | 配送日期 |
| `delivery_timestamp` | BIGINT | 配送日期（时间戳格式） |
| `expect_receive_time` | STRING | 期望收货时间 |
| `sign_time` | BIGINT | 签到送达时间（时间戳，可判断晚点） |
| `sign_distance` | INT | 签到距离（米） |
| `service_time` | BIGINT | 送达时间（时间戳，运力池标准，比sign_time略滞后） |
| `operate_timestamp` | BIGINT | 收货确认时间（时间戳） |
| `operate_time` | STRING | 收货确认时间 |
| `operate_date` | STRING | 收货确认日期 |

#### 五、物流节点（仓→站→线→区，12字段）

| 字段名 | 类型 | 说明 |
|--------|------|------|
| `warehouse_id` | BIGINT | 仓库ID |
| `warehouse_name` | STRING | 仓名称 |
| `site_id` | BIGINT | 站点ID |
| `site_name` | STRING | 站点名称 |
| `site_type` | BIGINT | 站点类型：20卫星城, 30代理人 |
| `station_region_id` | BIGINT | 站区ID |
| `station_region_name` | STRING | 站区名称 |
| `area_id` | BIGINT | 服务区ID |
| `area_distance` | DECIMAL(30,6) | 仓到服务区距离（米） |
| `route_id` | BIGINT | 线路ID |
| `route_name` | STRING | 线路名称 |
| `region_id` | BIGINT | 配送区域ID |
| `sale_area_id` | BIGINT | 售卖区ID |
| `city_id` | BIGINT | 城市ID |

#### 六、人员车辆（8字段）

| 字段名 | 类型 | 说明 |
|--------|------|------|
| `driver_no` | BIGINT | 司机编号（数据被截取） |
| `driver_code` | STRING | **完整司机编号（用此字段）** |
| `driver_name` | STRING | 司机名称 |
| `car_no` | STRING | 车牌号 |
| `cartype_no` | STRING | 车次号 |
| `cartype_name` | STRING | 车型名称 |
| `wiring_operator_id` | BIGINT | 排线人ID |
| `start_car_operator_id` | BIGINT | 排车人ID |

#### 七、状态与类型（14字段）

| 字段名 | 类型 | 说明 |
|--------|------|------|
| `waybill_status` | STRING | 运单状态：10接单完成, 20已排线, 30已排车, 40已发车, 50已到站点, 55配送中, 60妥投, 61全拒, 62半拒, 70代收款完成, 80回交物资, 90回交代收款, 100完成/电子账单完成 |
| `status` | BIGINT | 任务单状态：5新建, 10等待排车, 20排车完成, 30取货完成, 35支线配送中, 40到达站点, 43站长收货完成, 46配送员收货, 50配送员配送中, 60已完成(交货) |
| `distribute_type` | BIGINT | **配送类型：10直送, 20支线, 25末端** |
| `distribution_type` | BIGINT | ⚠️ 不推荐！用 distribute_type |
| `batch_id` | BIGINT | 配送批次：-1全批次, 1晨鲜送, 7下午送, 13夜间配, 16当日下午送, 19卫星城, 20冷鲜送, 23晨鲜送C端 |
| `wave_id` | BIGINT | 生产波次ID |
| `wave_name` | STRING | 生产波次名称 |
| `customer_type` | BIGINT | 商户类型：2家庭个人, 1非家庭个人 |
| `receive_customer_type` | BIGINT | 收货客户类型：10美菜 |
| `sale_type` | BIGINT | 商户类型：1普通大客户, 2合伙人城市客户, 3中小客户, 20分销, 21多级分销, 22品类大客户 |
| `sell_type` | BIGINT | 经营模式：1自营, 2~7 POP合作(2FBP代开, 3FBP自开, 4SOP代开, 5SOP自开, 6LBP代开, 7LBP自开) |
| `owner_id` | BIGINT | 1自营, >1 POP商 |
| `is_deleted` | BIGINT | 是否删除 |
| `ts` | STRING | 时间戳 |
