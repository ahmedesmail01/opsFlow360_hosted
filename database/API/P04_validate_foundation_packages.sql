--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P04 - Foundation Package Validation
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Safety: Read-only.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 01. Exact object inventory
-- Expected: ACTUAL_VALUE = 9, EXPECTED_VALUE = 9, RESULT = PASS.
--------------------------------------------------------------------------------

select 'P04_VALID_OBJECTS' check_name,
       count(*) actual_value,
       9 expected_value,
       case when count(*) = 9 then 'PASS' else 'FAIL' end result
  from user_objects
 where object_name in (
   'OF_UTIL_API', 'OF_SECURITY_API', 'OF_AUDIT_API', 'OF_ERROR_API',
   'OF_AUDIT_LOG_GUARD_TRG'
 )
   and object_type in ('PACKAGE', 'PACKAGE BODY', 'TRIGGER')
   and status = 'VALID';

--------------------------------------------------------------------------------
-- 02. Expected type breakdown
-- Expected: PACKAGE=4, PACKAGE BODY=4, TRIGGER=1; every row PASS.
--------------------------------------------------------------------------------

select object_type,
       count(*) actual_value,
       case object_type
         when 'PACKAGE' then 4
         when 'PACKAGE BODY' then 4
         when 'TRIGGER' then 1
       end expected_value,
       case
         when object_type = 'PACKAGE' and count(*) = 4 then 'PASS'
         when object_type = 'PACKAGE BODY' and count(*) = 4 then 'PASS'
         when object_type = 'TRIGGER' and count(*) = 1 then 'PASS'
         else 'FAIL'
       end result
  from user_objects
 where object_name in (
   'OF_UTIL_API', 'OF_SECURITY_API', 'OF_AUDIT_API', 'OF_ERROR_API',
   'OF_AUDIT_LOG_GUARD_TRG'
 )
   and object_type in ('PACKAGE', 'PACKAGE BODY', 'TRIGGER')
 group by object_type
 order by object_type;

--------------------------------------------------------------------------------
-- 03. Compile diagnostics
-- Expected: no rows. Any row is a blocking compile error.
--------------------------------------------------------------------------------

select name,
       type,
       line,
       position,
       text
  from user_errors
 where name in (
   'OF_UTIL_API', 'OF_SECURITY_API', 'OF_AUDIT_API', 'OF_ERROR_API',
   'OF_AUDIT_LOG_GUARD_TRG'
 )
 order by name, type, sequence;

--------------------------------------------------------------------------------
-- 04. Definer-rights boundary
-- Expected: 4 package specifications declare AUTHID DEFINER.
--------------------------------------------------------------------------------

select 'AUTHID_DEFINER_SPECS' check_name,
       count(*) actual_value,
       4 expected_value,
       case when count(*) = 4 then 'PASS' else 'FAIL' end result
  from user_source
 where name in (
   'OF_UTIL_API', 'OF_SECURITY_API', 'OF_AUDIT_API', 'OF_ERROR_API'
 )
   and type = 'PACKAGE'
   and upper(text) like '%AUTHID DEFINER%';

--------------------------------------------------------------------------------
-- 05. Audit guard state
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
 where t.trigger_name = 'OF_AUDIT_LOG_GUARD_TRG';

--------------------------------------------------------------------------------
-- 06. Utility and typed-setting smoke checks
-- Expected: all result columns are PASS.
--------------------------------------------------------------------------------

select of_util_api.normalize_code('  service_agent ') normalized_code,
       of_util_api.get_setting_text('DEFAULT_LOCALE') default_locale,
       of_util_api.get_setting_number('SLA_WARNING_PERCENT') warning_percent,
       length(of_util_api.new_correlation_id()) correlation_length,
       case
         when of_util_api.normalize_code('  service_agent ') = 'SERVICE_AGENT'
          and of_util_api.get_setting_text('DEFAULT_LOCALE') = 'en'
          and of_util_api.get_setting_number('SLA_WARNING_PERCENT') = 80
          and length(of_util_api.new_correlation_id()) = 32
         then 'PASS'
         else 'FAIL'
       end result
  from dual;

--------------------------------------------------------------------------------
-- 07. Server identity observation
-- A null CURRENT_USER_ID is normal before your real APEX account is mapped in
-- P08. The important rule is that the username comes from server context.
--------------------------------------------------------------------------------

select of_security_api.current_username() current_server_username,
       of_security_api.current_user_id() current_user_id,
       case
         when of_security_api.current_user_id() is null
         then 'NOT_YET_MAPPED (EXPECTED BEFORE P08)'
         else 'ACTIVE_USER_MAPPED'
       end mapping_status
  from dual;

--------------------------------------------------------------------------------
-- 08. Required P03 role and setting inputs
-- Expected: ROLES=6 PASS and APP_SETTINGS=5 PASS.
--------------------------------------------------------------------------------

select 'ACTIVE_ROLES' entity_name,
       count(*) actual_value,
       6 expected_value,
       case when count(*) = 6 then 'PASS' else 'FAIL' end result
  from of_roles
 where is_active = 'Y'
union all
select 'APP_SETTINGS',
       count(*),
       5,
       case when count(*) = 5 then 'PASS' else 'FAIL' end
  from of_app_settings
 where setting_code in (
   'DEFAULT_LOCALE', 'DEFAULT_TIMEZONE', 'TICKET_PREFIX',
   'SLA_WARNING_PERCENT', 'ENABLE_EMAIL_NOTIFICATIONS'
 );

--------------------------------------------------------------------------------
-- 09. P04 test-residue check
-- Expected: three rows, every ACTUAL_VALUE=0 and RESULT=PASS.
--------------------------------------------------------------------------------

select 'TEST_TICKETS' entity_name,
       count(*) actual_value,
       0 expected_value,
       case when count(*) = 0 then 'PASS' else 'FAIL' end result
  from of_tickets
 where ticket_no like 'TKT-P04-%'
union all
select 'TEST_AUDIT_ROWS',
       count(*),
       0,
       case when count(*) = 0 then 'PASS' else 'FAIL' end
  from of_audit_log
 where action_code in ('P04_TEST', 'P04_DIRECT_TEST')
union all
select 'TEST_ERROR_ROWS',
       count(*),
       0,
       case when count(*) = 0 then 'PASS' else 'FAIL' end
  from of_error_log
 where location_code = 'P04.TEST.ERROR_HANDLER';

--------------------------------------------------------------------------------
-- End P04 validator. Expected SQL Scripts statements: 9.
--------------------------------------------------------------------------------
