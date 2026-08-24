--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P06 - Asset Lifecycle Validation
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Safety: Read-only.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 01. Exact P06 table inventory
-- Expected: 6/6 PASS.
--------------------------------------------------------------------------------

select 'P06_TABLES' check_name,
       count(*) actual_value,
       6 expected_value,
       case when count(*) = 6 then 'PASS' else 'FAIL' end result
  from user_tables
 where table_name in (
   'OF_ASSET_TYPES', 'OF_ASSETS', 'OF_ASSET_RESERVATIONS',
   'OF_ASSET_ASSIGNMENTS', 'OF_ASSET_REPAIRS',
   'OF_ASSET_STATUS_HISTORY'
 );

--------------------------------------------------------------------------------
-- 02. Exact P06 code-object inventory
-- Expected: 3/3 VALID.
--------------------------------------------------------------------------------

select 'P06_VALID_CODE_OBJECTS' check_name,
       count(*) actual_value,
       3 expected_value,
       case when count(*) = 3 then 'PASS' else 'FAIL' end result
  from user_objects
 where object_name in ('OF_ASSET_API', 'OF_ASSET_HISTORY_GUARD_TRG')
   and object_type in ('PACKAGE', 'PACKAGE BODY', 'TRIGGER')
   and status = 'VALID';

--------------------------------------------------------------------------------
-- 03. Compile diagnostics
-- Expected: no rows.
--------------------------------------------------------------------------------

select name, type, line, position, text
  from user_errors
 where name in ('OF_ASSET_API', 'OF_ASSET_HISTORY_GUARD_TRG')
 order by name, type, sequence;

--------------------------------------------------------------------------------
-- 04. Public API inventory
-- Expected: 11 named action routines and PASS.
--------------------------------------------------------------------------------

select 'P06_PUBLIC_ACTIONS' check_name,
       count(*) actual_value,
       11 expected_value,
       case when count(*) = 11 then 'PASS' else 'FAIL' end result
  from user_procedures
 where object_name = 'OF_ASSET_API'
   and procedure_name in (
     'REGISTER_ASSET', 'RESERVE_ASSET', 'RELEASE_RESERVATION',
     'ASSIGN_ASSET', 'TRANSFER_ASSET', 'RETURN_ASSET', 'OPEN_REPAIR',
     'COMPLETE_REPAIR_TO_STOCK', 'COMPLETE_REPAIR_TO_CUSTODIAN',
     'MARK_LOST', 'RETIRE_ASSET'
   );

--------------------------------------------------------------------------------
-- 05. Definer-rights boundary
-- Expected: 1/1 PASS.
--------------------------------------------------------------------------------

select 'P06_AUTHID_DEFINER' check_name,
       count(*) actual_value,
       1 expected_value,
       case when count(*) = 1 then 'PASS' else 'FAIL' end result
  from user_source
 where name = 'OF_ASSET_API'
   and type = 'PACKAGE'
   and upper(text) like '%AUTHID DEFINER%';

--------------------------------------------------------------------------------
-- 06. History guard health
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
 where t.trigger_name = 'OF_ASSET_HISTORY_GUARD_TRG';

--------------------------------------------------------------------------------
-- 07. Reference seed
-- Expected: 6 active required types.
--------------------------------------------------------------------------------

select 'P06_ACTIVE_ASSET_TYPES' check_name,
       count(*) actual_value,
       6 expected_value,
       case when count(*) = 6 then 'PASS' else 'FAIL' end result
  from of_asset_types
 where code in (
   'LAPTOP', 'DESKTOP', 'MONITOR', 'MOBILE_PHONE', 'PRINTER', 'FURNITURE'
 )
   and is_active = 'Y';

--------------------------------------------------------------------------------
-- 08. Exclusive-active-relation unique indexes
-- Expected: 3/3 VALID UNIQUE indexes.
--------------------------------------------------------------------------------

select 'P06_EXCLUSIVE_INDEXES' check_name,
       count(*) actual_value,
       3 expected_value,
       case when count(*) = 3 then 'PASS' else 'FAIL' end result
  from user_indexes
 where index_name in (
   'OF_ASSET_RES_ACTIVE_UIX',
   'OF_ASSET_ASG_ACTIVE_UIX',
   'OF_ASSET_REP_ACTIVE_UIX'
 )
   and uniqueness = 'UNIQUE'
   and status = 'VALID';

--------------------------------------------------------------------------------
-- 09. P04 and P05 dependencies remain valid
-- Expected: 12/12 PASS.
--------------------------------------------------------------------------------

select 'P04_P05_DEPENDENCIES_VALID' check_name,
       count(*) actual_value,
       12 expected_value,
       case when count(*) = 12 then 'PASS' else 'FAIL' end result
  from user_objects
 where object_name in (
   'OF_UTIL_API', 'OF_SECURITY_API', 'OF_AUDIT_API', 'OF_ERROR_API',
   'OF_AUDIT_LOG_GUARD_TRG', 'OF_TICKET_API',
   'OF_TICKET_HISTORY_GUARD_TRG'
 )
   and object_type in ('PACKAGE', 'PACKAGE BODY', 'TRIGGER')
   and status = 'VALID';

--------------------------------------------------------------------------------
-- 10. Current state agrees with all active temporal relationships
-- Expected: zero invalid assets.
--------------------------------------------------------------------------------

select 'ASSET_ACTIVE_RELATION_MISMATCH' check_name,
       count(*) actual_value,
       0 expected_value,
       case when count(*) = 0 then 'PASS' else 'FAIL' end result
  from (
    select a.id,
           a.status_code,
           (select count(*)
              from of_asset_reservations r
             where r.asset_id = a.id and r.status_code = 'ACTIVE') active_res,
           (select count(*)
              from of_asset_assignments s
             where s.asset_id = a.id and s.returned_at is null) active_asg,
           (select count(*)
              from of_asset_repairs p
             where p.asset_id = a.id
               and p.status_code in ('OPEN', 'IN_PROGRESS')) active_rep
      from of_assets a
  ) x
 where not (
   (status_code = 'IN_STOCK' and active_res = 0 and active_asg = 0 and active_rep = 0)
   or (status_code = 'RESERVED' and active_res = 1 and active_asg = 0 and active_rep = 0)
   or (status_code = 'ASSIGNED' and active_res = 0 and active_asg = 1 and active_rep = 0)
   or (status_code = 'IN_REPAIR' and active_res = 0 and active_asg = 0 and active_rep = 1)
   or (status_code in ('RETIRED', 'LOST')
       and active_res = 0 and active_asg = 0 and active_rep = 0)
 );

--------------------------------------------------------------------------------
-- 11. Initial/latest history reconciliation
-- Expected: both counts zero.
--------------------------------------------------------------------------------

select 'ASSETS_WITHOUT_INITIAL_HISTORY' check_name,
       count(*) actual_value,
       0 expected_value,
       case when count(*) = 0 then 'PASS' else 'FAIL' end result
  from of_assets a
 where not exists (
   select 1
     from of_asset_status_history h
    where h.asset_id = a.id
      and h.from_status_code is null
      and h.to_status_code = 'IN_STOCK'
 )
union all
select 'LATEST_ASSET_HISTORY_MISMATCH',
       count(*),
       0,
       case when count(*) = 0 then 'PASS' else 'FAIL' end
  from of_assets a
 where nvl(a.status_code, '#') <> nvl(
   (
     select max(h.to_status_code) keep (
              dense_rank last order by h.changed_at, h.id
            )
       from of_asset_status_history h
      where h.asset_id = a.id
   ),
   '#'
 );

--------------------------------------------------------------------------------
-- 12. P06 test residue
-- Expected: every count zero.
--------------------------------------------------------------------------------

select 'P06_TEST_ASSETS' entity_name,
       count(*) actual_value,
       0 expected_value,
       case when count(*) = 0 then 'PASS' else 'FAIL' end result
  from of_assets
 where asset_tag like 'AST-P06T-%'
union all
select 'P06_TEST_AUDIT_ROWS',
       count(*),
       0,
       case when count(*) = 0 then 'PASS' else 'FAIL' end
  from of_audit_log
 where entity_type_code = 'ASSET'
   and entity_key like 'AST-P06T-%';

--------------------------------------------------------------------------------
-- End P06 validator. Expected SQL Scripts statements: 12.
--------------------------------------------------------------------------------
