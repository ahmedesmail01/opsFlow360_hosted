--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P07 - Procurement, Receiving, and Inventory Validation
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Safety: Read-only.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 01. Exact P07 table inventory
-- Expected: 11/11 PASS.
--------------------------------------------------------------------------------

select 'P07_TABLES' check_name,
       count(*) actual_value,
       11 expected_value,
       case when count(*) = 11 then 'PASS' else 'FAIL' end result
  from user_tables
 where table_name in (
   'OF_CATALOG_ITEMS', 'OF_SUPPLIERS', 'OF_PURCHASE_REQUESTS',
   'OF_PURCHASE_REQUEST_ITEMS', 'OF_APPROVALS', 'OF_PURCHASE_ORDERS',
   'OF_PURCHASE_ORDER_ITEMS', 'OF_GOODS_RECEIPTS',
   'OF_GOODS_RECEIPT_ITEMS', 'OF_STOCK_MOVEMENTS',
   'OF_INVENTORY_BALANCES'
 );

--------------------------------------------------------------------------------
-- 02. Exact P07 code-object inventory
-- Expected: 5/5 VALID (two package specs, two bodies, one trigger).
--------------------------------------------------------------------------------

select 'P07_VALID_CODE_OBJECTS' check_name,
       count(*) actual_value,
       5 expected_value,
       case when count(*) = 5 then 'PASS' else 'FAIL' end result
  from user_objects
 where object_name in (
   'OF_PROCUREMENT_API', 'OF_INVENTORY_API',
   'OF_STOCK_MOVEMENT_GUARD_TRG'
 )
   and object_type in ('PACKAGE', 'PACKAGE BODY', 'TRIGGER')
   and status = 'VALID';

--------------------------------------------------------------------------------
-- 03. Compile diagnostics
-- Expected: no rows.
--------------------------------------------------------------------------------

select name, type, line, position, text
  from user_errors
 where name in (
   'OF_PROCUREMENT_API', 'OF_INVENTORY_API',
   'OF_STOCK_MOVEMENT_GUARD_TRG'
 )
 order by name, type, sequence;

--------------------------------------------------------------------------------
-- 04. Procurement public-action inventory
-- Expected: 15/15 PASS.
--------------------------------------------------------------------------------

select 'P07_PROCUREMENT_ACTIONS' check_name,
       count(*) actual_value,
       15 expected_value,
       case when count(*) = 15 then 'PASS' else 'FAIL' end result
  from user_procedures
 where object_name = 'OF_PROCUREMENT_API'
   and procedure_name in (
     'CREATE_REQUEST_DRAFT', 'ADD_REQUEST_ITEM', 'REMOVE_REQUEST_ITEM',
     'SUBMIT_REQUEST', 'APPROVE_MANAGER', 'APPROVE_OPERATIONS',
     'APPROVE_PROCUREMENT', 'REJECT_REQUEST', 'CANCEL_REQUEST',
     'CREATE_ORDER_DRAFT', 'ADD_ORDER_ITEM', 'ISSUE_ORDER',
     'CANCEL_ORDER', 'CLOSE_ORDER', 'CLOSE_REQUEST'
   );

--------------------------------------------------------------------------------
-- 05. Inventory public-action inventory
-- Expected: 4/4 PASS.
--------------------------------------------------------------------------------

select 'P07_INVENTORY_ACTIONS' check_name,
       count(*) actual_value,
       4 expected_value,
       case when count(*) = 4 then 'PASS' else 'FAIL' end result
  from user_procedures
 where object_name = 'OF_INVENTORY_API'
   and procedure_name in (
     'CREATE_RECEIPT_DRAFT', 'ADD_RECEIPT_ITEM',
     'POST_RECEIPT', 'VOID_RECEIPT'
   );

--------------------------------------------------------------------------------
-- 06. Definer-rights boundaries
-- Expected: 2/2 PASS.
--------------------------------------------------------------------------------

select 'P07_AUTHID_DEFINER' check_name,
       count(*) actual_value,
       2 expected_value,
       case when count(*) = 2 then 'PASS' else 'FAIL' end result
  from user_source
 where name in ('OF_PROCUREMENT_API', 'OF_INVENTORY_API')
   and type = 'PACKAGE'
   and upper(text) like '%AUTHID DEFINER%';

--------------------------------------------------------------------------------
-- 07. Immutable-ledger guard health
-- Expected: ENABLED + VALID + PASS.
--------------------------------------------------------------------------------

select t.trigger_name,
       t.status trigger_status,
       o.status object_status,
       case
         when t.status = 'ENABLED' and o.status = 'VALID' then 'PASS'
         else 'FAIL'
       end result
  from user_triggers t
  join user_objects o
    on o.object_name = t.trigger_name
   and o.object_type = 'TRIGGER'
 where t.trigger_name = 'OF_STOCK_MOVEMENT_GUARD_TRG';

--------------------------------------------------------------------------------
-- 08. Reference seed
-- Expected: settings/catalog/suppliers = 5/6/3, all PASS.
--------------------------------------------------------------------------------

select 'P07_SETTINGS' check_name, count(*) actual_value, 5 expected_value,
       case when count(*) = 5 then 'PASS' else 'FAIL' end result
  from of_app_settings
 where setting_code in (
   'PURCHASE_REQUEST_PREFIX', 'PURCHASE_ORDER_PREFIX',
   'GOODS_RECEIPT_PREFIX', 'PROCUREMENT_APPROVAL_THRESHOLD',
   'APPROVAL_DUE_DAYS'
 )
union all
select 'P07_ACTIVE_CATALOG_ITEMS', count(*), 6,
       case when count(*) = 6 then 'PASS' else 'FAIL' end
  from of_catalog_items
 where code in (
   'OFFICE_PAPER_A4', 'BLACK_TONER', 'USB_C_DOCK',
   'SAFETY_KIT', 'STANDARD_LAPTOP', 'OFFICE_CHAIR'
 ) and is_active = 'Y'
union all
select 'P07_ACTIVE_SUPPLIERS', count(*), 3,
       case when count(*) = 3 then 'PASS' else 'FAIL' end
  from of_suppliers
 where supplier_code in ('NILE_TECH', 'DELTA_OFFICE', 'CAIRO_SUPPLY')
   and is_active = 'Y';

--------------------------------------------------------------------------------
-- 09. Idempotency and ledger uniqueness indexes
-- Expected: 3/3 VALID UNIQUE indexes.
--------------------------------------------------------------------------------

select 'P07_CONTROL_INDEXES' check_name,
       count(*) actual_value,
       3 expected_value,
       case when count(*) = 3 then 'PASS' else 'FAIL' end result
  from user_indexes
 where index_name in (
   'OF_APPROVAL_PENDING_UIX',
   'OF_STOCK_RECEIPT_UIX',
   'OF_STOCK_REVERSAL_UIX'
 )
   and uniqueness = 'UNIQUE'
   and status = 'VALID';

--------------------------------------------------------------------------------
-- 10. P04-P06 dependencies remain valid
-- Expected: 15/15 PASS.
--------------------------------------------------------------------------------

select 'P04_P06_DEPENDENCIES_VALID' check_name,
       count(*) actual_value,
       15 expected_value,
       case when count(*) = 15 then 'PASS' else 'FAIL' end result
  from user_objects
 where object_name in (
   'OF_UTIL_API', 'OF_SECURITY_API', 'OF_AUDIT_API', 'OF_ERROR_API',
   'OF_AUDIT_LOG_GUARD_TRG', 'OF_TICKET_API',
   'OF_TICKET_HISTORY_GUARD_TRG', 'OF_ASSET_API',
   'OF_ASSET_HISTORY_GUARD_TRG'
 )
   and object_type in ('PACKAGE', 'PACKAGE BODY', 'TRIGGER')
   and status = 'VALID';

--------------------------------------------------------------------------------
-- 11. Deferred P06 procurement foreign keys
-- Expected: 2/2 ENABLED and VALIDATED.
--------------------------------------------------------------------------------

select 'P07_DEFERRED_FOREIGN_KEYS' check_name,
       count(*) actual_value,
       2 expected_value,
       case when count(*) = 2 then 'PASS' else 'FAIL' end result
  from user_constraints
 where constraint_name in ('OF_ASSETS_PO_ITEM_FK', 'OF_ASSET_REP_SUPPLIER_FK')
   and constraint_type = 'R'
   and status = 'ENABLED'
   and validated = 'VALIDATED';

--------------------------------------------------------------------------------
-- 12. Request headers reconcile to request lines
-- Expected: zero mismatches.
--------------------------------------------------------------------------------

select 'PURCHASE_REQUEST_TOTAL_MISMATCH' check_name,
       count(*) actual_value,
       0 expected_value,
       case when count(*) = 0 then 'PASS' else 'FAIL' end result
  from of_purchase_requests pr
 where pr.total_amount <>
       (select coalesce(sum(pri.line_total), 0)
          from of_purchase_request_items pri
         where pri.purchase_request_id = pr.id);

--------------------------------------------------------------------------------
-- 13. Order headers reconcile to order lines
-- Expected: zero mismatches.
--------------------------------------------------------------------------------

select 'PURCHASE_ORDER_TOTAL_MISMATCH' check_name,
       count(*) actual_value,
       0 expected_value,
       case when count(*) = 0 then 'PASS' else 'FAIL' end result
  from of_purchase_orders po
 where po.total_amount <>
       (select coalesce(sum(poi.line_total), 0)
          from of_purchase_order_items poi
         where poi.purchase_order_id = po.id);

--------------------------------------------------------------------------------
-- 14. Noncancelled order quantities cannot exceed request quantities
-- Expected: zero overcommitted request items.
--------------------------------------------------------------------------------

select 'PURCHASE_ORDER_OVERCOMMIT' check_name,
       count(*) actual_value,
       0 expected_value,
       case when count(*) = 0 then 'PASS' else 'FAIL' end result
  from of_purchase_request_items pri
 where pri.quantity < (
   select coalesce(sum(poi.ordered_quantity), 0)
     from of_purchase_order_items poi
     join of_purchase_orders po on po.id = poi.purchase_order_id
    where poi.request_item_id = pri.id
      and po.status_code <> 'CANCELLED'
 );

--------------------------------------------------------------------------------
-- 15. Receipt line arithmetic and rejection evidence
-- Expected: zero invalid lines.
--------------------------------------------------------------------------------

select 'GOODS_RECEIPT_LINE_MISMATCH' check_name,
       count(*) actual_value,
       0 expected_value,
       case when count(*) = 0 then 'PASS' else 'FAIL' end result
  from of_goods_receipt_items
 where quantity_received <= 0
    or quantity_accepted < 0
    or quantity_rejected < 0
    or quantity_received <> quantity_accepted + quantity_rejected
    or (quantity_rejected > 0 and trim(rejection_reason) is null);

--------------------------------------------------------------------------------
-- 16. Posted accepted quantities cannot exceed order quantities
-- Expected: zero over-received order items.
--------------------------------------------------------------------------------

select 'GOODS_RECEIPT_OVERACCEPT' check_name,
       count(*) actual_value,
       0 expected_value,
       case when count(*) = 0 then 'PASS' else 'FAIL' end result
  from of_purchase_order_items poi
 where poi.ordered_quantity < (
   select coalesce(sum(gri.quantity_accepted), 0)
     from of_goods_receipt_items gri
     join of_goods_receipts gr
       on gr.id = gri.goods_receipt_id
      and gr.status_code = 'POSTED'
    where gri.purchase_order_item_id = poi.id
 );

--------------------------------------------------------------------------------
-- 17. Pending approvals agree with the request's current review stage
-- Expected: zero routing mismatches.
--------------------------------------------------------------------------------

select 'PENDING_APPROVAL_STATE_MISMATCH' check_name,
       count(*) actual_value,
       0 expected_value,
       case when count(*) = 0 then 'PASS' else 'FAIL' end result
  from of_purchase_requests pr
 where (
   pr.status_code in ('MANAGER_REVIEW', 'OPERATIONS_REVIEW', 'PROCUREMENT_REVIEW')
   and not exists (
     select 1
       from of_approvals a
      where a.purchase_request_id = pr.id
        and a.status_code = 'PENDING'
        and a.stage_code = case pr.status_code
          when 'MANAGER_REVIEW' then 'MANAGER'
          when 'OPERATIONS_REVIEW' then 'OPERATIONS'
          when 'PROCUREMENT_REVIEW' then 'PROCUREMENT'
        end
   )
 )
 or (
   pr.status_code not in ('MANAGER_REVIEW', 'OPERATIONS_REVIEW', 'PROCUREMENT_REVIEW')
   and exists (
     select 1 from of_approvals a
      where a.purchase_request_id = pr.id
        and a.status_code = 'PENDING'
   )
 )
 or pr.status_code = 'SUBMITTED'
union all
select 'PROCUREMENT_RECEIVING_STATE_MISMATCH',
       count(*),
       0,
       case when count(*) = 0 then 'PASS' else 'FAIL' end
  from (
    select po.id
      from (
        select po.id, po.status_code,
               (select count(*)
                  from of_purchase_order_items poi
                 where poi.purchase_order_id = po.id) line_count,
               (select count(*)
                  from of_purchase_order_items poi
                 where poi.purchase_order_id = po.id
                   and poi.ordered_quantity > (
                     select coalesce(sum(gri.quantity_accepted), 0)
                       from of_goods_receipt_items gri
                       join of_goods_receipts gr
                         on gr.id = gri.goods_receipt_id
                        and gr.status_code = 'POSTED'
                      where gri.purchase_order_item_id = poi.id
                   )) incomplete_count,
               (select coalesce(sum(gri.quantity_accepted), 0)
                  from of_goods_receipt_items gri
                  join of_goods_receipts gr
                    on gr.id = gri.goods_receipt_id
                   and gr.status_code = 'POSTED'
                  join of_purchase_order_items poi
                    on poi.id = gri.purchase_order_item_id
                 where poi.purchase_order_id = po.id) accepted_total
          from of_purchase_orders po
         where po.status_code in (
           'ISSUED', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CLOSED'
         )
      ) po
     where (case when po.status_code = 'CLOSED'
                 then 'RECEIVED' else po.status_code end) <>
           (case
              when po.line_count > 0 and po.incomplete_count = 0
                then 'RECEIVED'
              when po.accepted_total > 0 then 'PARTIALLY_RECEIVED'
              else 'ISSUED'
            end)
    union all
    select pr.id
      from (
        select pr.id, pr.status_code,
               (select count(*)
                  from of_purchase_request_items pri
                 where pri.purchase_request_id = pr.id) line_count,
               (select count(*)
                  from of_purchase_request_items pri
                 where pri.purchase_request_id = pr.id
                   and pri.quantity > (
                     select coalesce(sum(poi.ordered_quantity), 0)
                       from of_purchase_order_items poi
                       join of_purchase_orders po
                         on po.id = poi.purchase_order_id
                        and po.status_code in (
                          'ISSUED', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CLOSED'
                        )
                      where poi.request_item_id = pri.id
                   )) underordered_count,
               (select coalesce(sum(poi.ordered_quantity), 0)
                  from of_purchase_order_items poi
                  join of_purchase_orders po
                    on po.id = poi.purchase_order_id
                   and po.status_code in (
                     'ISSUED', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CLOSED'
                   )
                 where po.purchase_request_id = pr.id) issued_quantity,
               (select coalesce(sum(gri.quantity_accepted), 0)
                  from of_goods_receipt_items gri
                  join of_goods_receipts gr
                    on gr.id = gri.goods_receipt_id
                   and gr.status_code = 'POSTED'
                  join of_purchase_order_items poi
                    on poi.id = gri.purchase_order_item_id
                  join of_purchase_orders po on po.id = poi.purchase_order_id
                 where po.purchase_request_id = pr.id
                   and po.status_code <> 'CANCELLED') accepted_quantity,
               (select count(*)
                  from of_purchase_orders po
                 where po.purchase_request_id = pr.id
                   and po.status_code not in ('DRAFT', 'CANCELLED')) active_orders,
               (select count(*)
                  from of_purchase_orders po
                 where po.purchase_request_id = pr.id
                   and po.status_code not in (
                     'DRAFT', 'CANCELLED', 'RECEIVED', 'CLOSED'
                   )) not_received_orders
          from of_purchase_requests pr
         where pr.status_code in (
           'APPROVED', 'PARTIALLY_ORDERED', 'ORDERED',
           'PARTIALLY_RECEIVED', 'RECEIVED', 'CLOSED'
         )
      ) pr
     where (case when pr.status_code = 'CLOSED'
                 then 'RECEIVED' else pr.status_code end) <>
           (case
              when pr.line_count > 0 and pr.underordered_count = 0
                   and pr.active_orders > 0 and pr.not_received_orders = 0
                then 'RECEIVED'
              when pr.accepted_quantity > 0 then 'PARTIALLY_RECEIVED'
              when pr.line_count > 0 and pr.underordered_count = 0
                then 'ORDERED'
              when pr.issued_quantity > 0 then 'PARTIALLY_ORDERED'
              else 'APPROVED'
            end)
  );

--------------------------------------------------------------------------------
-- 18. Current balances reconcile to the immutable movement ledger
-- Expected: zero mismatches.
--------------------------------------------------------------------------------

select 'INVENTORY_LEDGER_BALANCE_MISMATCH' check_name,
       count(*) actual_value,
       0 expected_value,
       case when count(*) = 0 then 'PASS' else 'FAIL' end result
  from (
    select coalesce(b.catalog_item_id, m.catalog_item_id) catalog_item_id,
           coalesce(b.location_id, m.location_id) location_id,
           coalesce(b.quantity_on_hand, 0) balance_quantity,
           coalesce(m.ledger_quantity, 0) ledger_quantity
      from of_inventory_balances b
      full outer join (
        select catalog_item_id, location_id,
               sum(quantity_delta) ledger_quantity
          from of_stock_movements
         group by catalog_item_id, location_id
      ) m
        on m.catalog_item_id = b.catalog_item_id
       and m.location_id = b.location_id
  ) x
 where x.balance_quantity <> x.ledger_quantity;

--------------------------------------------------------------------------------
-- 19. Receipt-to-ledger and reversal linkage
-- Expected: zero evidence mismatches.
--------------------------------------------------------------------------------

select 'RECEIPT_LEDGER_LINK_MISMATCH' check_name,
       count(*) actual_value,
       0 expected_value,
       case when count(*) = 0 then 'PASS' else 'FAIL' end result
  from (
    select 'POSTED_STOCKED_LINE_MISSING' issue_type, gri.id evidence_id
      from of_goods_receipt_items gri
      join of_goods_receipts gr on gr.id = gri.goods_receipt_id
      join of_purchase_order_items poi on poi.id = gri.purchase_order_item_id
      join of_catalog_items ci on ci.id = poi.catalog_item_id
     where gr.status_code = 'POSTED'
       and ci.is_stocked = 'Y'
       and gri.quantity_accepted > 0
       and not exists (
         select 1 from of_stock_movements sm
          where sm.receipt_item_id = gri.id
            and sm.movement_type_code = 'RECEIPT'
            and sm.catalog_item_id = poi.catalog_item_id
            and sm.location_id = gri.location_id
            and sm.quantity_delta = gri.quantity_accepted
       )
    union all
    select 'INVALID_RECEIPT_MOVEMENT', sm.id
      from of_stock_movements sm
      join of_goods_receipt_items gri on gri.id = sm.receipt_item_id
      join of_goods_receipts gr on gr.id = gri.goods_receipt_id
      join of_purchase_order_items poi on poi.id = gri.purchase_order_item_id
      join of_catalog_items ci on ci.id = poi.catalog_item_id
     where sm.movement_type_code = 'RECEIPT'
       and (
         gr.status_code not in ('POSTED', 'VOID')
         or ci.is_stocked <> 'Y'
         or sm.catalog_item_id <> poi.catalog_item_id
         or sm.location_id <> gri.location_id
         or sm.quantity_delta <> gri.quantity_accepted
       )
    union all
    select 'VOID_MOVEMENT_UNREVERSED', original.id
      from of_stock_movements original
      join of_goods_receipt_items gri on gri.id = original.receipt_item_id
      join of_goods_receipts gr on gr.id = gri.goods_receipt_id
     where original.movement_type_code = 'RECEIPT'
       and gr.status_code = 'VOID'
       and not exists (
         select 1 from of_stock_movements reversal
          where reversal.related_movement_id = original.id
            and reversal.movement_type_code = 'ADJUSTMENT'
            and reversal.catalog_item_id = original.catalog_item_id
            and reversal.location_id = original.location_id
            and reversal.receipt_item_id = original.receipt_item_id
            and reversal.quantity_delta = -original.quantity_delta
       )
    union all
    select 'INVALID_REVERSAL', reversal.id
      from of_stock_movements reversal
      join of_stock_movements original
        on original.id = reversal.related_movement_id
     where reversal.related_movement_id is not null
       and (
         reversal.movement_type_code <> 'ADJUSTMENT'
         or original.movement_type_code <> 'RECEIPT'
         or reversal.catalog_item_id <> original.catalog_item_id
         or reversal.location_id <> original.location_id
         or nvl(reversal.receipt_item_id, -1) <> nvl(original.receipt_item_id, -1)
         or reversal.quantity_delta <> -original.quantity_delta
       )
  );

--------------------------------------------------------------------------------
-- 20. P07 test residue
-- Expected: every count zero.
--------------------------------------------------------------------------------

select 'P07_TEST_REQUESTS' entity_name,
       count(*) actual_value,
       0 expected_value,
       case when count(*) = 0 then 'PASS' else 'FAIL' end result
  from of_purchase_requests
 where request_no like 'P07T-%'
union all
select 'P07_TEST_ORDERS', count(*), 0,
       case when count(*) = 0 then 'PASS' else 'FAIL' end
  from of_purchase_orders
 where po_no like 'P07PO-%'
union all
select 'P07_TEST_RECEIPTS', count(*), 0,
       case when count(*) = 0 then 'PASS' else 'FAIL' end
  from of_goods_receipts
 where receipt_no like 'P07GR-%'
union all
select 'P07_TEST_AUDIT_ROWS', count(*), 0,
       case when count(*) = 0 then 'PASS' else 'FAIL' end
  from of_audit_log
 where (entity_type_code = 'PURCHASE_REQUEST' and entity_key like 'P07T-%')
    or (entity_type_code = 'PURCHASE_ORDER' and entity_key like 'P07PO-%')
    or (entity_type_code = 'GOODS_RECEIPT' and entity_key like 'P07GR-%');

--------------------------------------------------------------------------------
-- End P07 validator. Expected SQL Scripts statements: 20.
--------------------------------------------------------------------------------
