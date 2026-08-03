with store_open_id as (
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
),

b_store_order_freq as (
  select cast(agent_user_id as bigint) as company_id,
         count(*) as b_order_cnt_30d
  from ods.ods_pay_core_t_pay_core_order
  where dt between 20260619 and 20260719
    and pay_amount > 0
    and pay_status in (2, 10)
    and agent_user_id is not null
    and agent_user_id != ''
    and agent_user_id regexp '^[0-9]+$'
  group by cast(agent_user_id as bigint)
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
  case when bf.b_order_cnt_30d > 10 then '是' else '否' end as `B门店下单频次高`,
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
left join b_store_order_freq bf on bf.company_id = t.second_company_id
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
