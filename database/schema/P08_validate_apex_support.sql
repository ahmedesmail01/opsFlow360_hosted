--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P08 - Database-Side APEX Support Validator
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Read only: yes
-- Note: APEX component checks are completed in App Builder using the P08 guide.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 01. P08 package object health
--------------------------------------------------------------------------------

select 'P08_VALID_OBJECTS' check_name,
       count(*) actual_value,
       2 expected_value,
       case when count(*) = 2 then 'PASS' else 'FAIL' end result
  from user_objects
 where object_name = 'OF_APEX_API'
   and object_type in ('PACKAGE', 'PACKAGE BODY')
   and status = 'VALID';

--------------------------------------------------------------------------------
-- 02. Compile diagnostics
-- Expected: no rows.
--------------------------------------------------------------------------------

select name,
       type,
       line,
       position,
       text
  from user_errors
 where name = 'OF_APEX_API'
 order by sequence;

--------------------------------------------------------------------------------
-- 03. Public API signature
--------------------------------------------------------------------------------

select 'P08_PUBLIC_ROUTINES' check_name,
       count(*) actual_value,
       5 expected_value,
       case when count(*) = 5 then 'PASS' else 'FAIL' end result
  from user_procedures
 where object_name = 'OF_APEX_API'
   and procedure_name in (
     'CURRENT_DISPLAY_NAME', 'CURRENT_LOCALE_CODE',
     'CURRENT_TIMEZONE_NAME', 'CURRENT_ROLE_CODES', 'HANDLE_ERROR'
   );

--------------------------------------------------------------------------------
-- 04. Bootstrap identity and required roles
--------------------------------------------------------------------------------

select 'P08_BOOTSTRAP_IDENTITY' check_name,
       count(*) actual_value,
       1 expected_value,
       case when count(*) = 1 then 'PASS' else 'FAIL' end result
  from of_app_users u
 where u.created_by = 'P08_BOOTSTRAP'
   and u.is_active = 'Y'
   and exists (
     select 1
       from of_user_roles ur
       join of_roles r on r.id = ur.role_id
      where ur.user_id = u.id
        and ur.is_active = 'Y'
        and r.code = 'EMPLOYEE'
        and r.is_active = 'Y'
   )
   and exists (
     select 1
       from of_user_roles ur
       join of_roles r on r.id = ur.role_id
      where ur.user_id = u.id
        and ur.is_active = 'Y'
        and r.code = 'OPERATIONS_ADMIN'
        and r.is_active = 'Y'
   );

--------------------------------------------------------------------------------
-- 05. Case-insensitive identity uniqueness
-- Expected: no rows.
--------------------------------------------------------------------------------

select upper(trim(username)) normalized_username,
       count(*) duplicate_count
  from of_app_users
 group by upper(trim(username))
having count(*) > 1;

--------------------------------------------------------------------------------
-- 06. P04-P08 code regression
--------------------------------------------------------------------------------

select object_name,
       object_type,
       status
  from user_objects
 where object_name in (
   'OF_UTIL_API', 'OF_SECURITY_API', 'OF_AUDIT_API', 'OF_ERROR_API',
   'OF_TICKET_API', 'OF_ASSET_API', 'OF_PROCUREMENT_API',
   'OF_INVENTORY_API', 'OF_APEX_API', 'OF_AUDIT_LOG_GUARD_TRG',
   'OF_TICKET_HISTORY_GUARD_TRG', 'OF_ASSET_HISTORY_GUARD_TRG',
   'OF_STOCK_MOVEMENT_GUARD_TRG'
 )
   and status <> 'VALID'
 order by object_name, object_type;

--------------------------------------------------------------------------------
-- 07. P07 test residue regression
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
-- End P08 validator. Expected SQL Scripts statements: 7.
--------------------------------------------------------------------------------
