--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P08 - APEX Application Support
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Creates: OF_APEX_API package specification and body
-- Safety: Requires a clean P07 schema. This script does not create the APEX app.
-- Rerun: CREATE OR REPLACE safely repairs the two P08 package objects.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 00. P07 acceptance-state database preflight
-- Manual gate still required: corrected P07.1 test PASS + final validator PASS.
--------------------------------------------------------------------------------

declare
  l_table_count       number;
  l_code_count        number;
  l_compile_errors    number;
  l_residue_count     number;
begin
  select count(*)
    into l_table_count
    from user_tables
   where table_name in (
     'OF_CATALOG_ITEMS', 'OF_SUPPLIERS', 'OF_PURCHASE_REQUESTS',
     'OF_PURCHASE_REQUEST_ITEMS', 'OF_APPROVALS', 'OF_PURCHASE_ORDERS',
     'OF_PURCHASE_ORDER_ITEMS', 'OF_GOODS_RECEIPTS',
     'OF_GOODS_RECEIPT_ITEMS', 'OF_STOCK_MOVEMENTS',
     'OF_INVENTORY_BALANCES'
   );

  select count(*)
    into l_code_count
    from user_objects
   where object_name in (
     'OF_UTIL_API', 'OF_SECURITY_API', 'OF_AUDIT_API', 'OF_ERROR_API',
     'OF_AUDIT_LOG_GUARD_TRG', 'OF_TICKET_API',
     'OF_TICKET_HISTORY_GUARD_TRG', 'OF_ASSET_API',
     'OF_ASSET_HISTORY_GUARD_TRG', 'OF_PROCUREMENT_API',
     'OF_INVENTORY_API', 'OF_STOCK_MOVEMENT_GUARD_TRG'
   )
     and object_type in ('PACKAGE', 'PACKAGE BODY', 'TRIGGER')
     and status = 'VALID';

  select count(*)
    into l_compile_errors
    from user_errors
   where name in (
     'OF_UTIL_API', 'OF_SECURITY_API', 'OF_AUDIT_API', 'OF_ERROR_API',
     'OF_TICKET_API', 'OF_ASSET_API', 'OF_PROCUREMENT_API',
     'OF_INVENTORY_API'
   );

  if l_table_count <> 11 then
    raise_application_error(
      -20480,
      'P08 stopped: expected 11 P07 tables, found ' || l_table_count || '.'
    );
  end if;

  if l_code_count <> 20 or l_compile_errors <> 0 then
    raise_application_error(
      -20481,
      'P08 stopped: expected 20 valid P04-P07 code objects and zero ' ||
      'compile errors; found ' || l_code_count || ' valid objects and ' ||
      l_compile_errors || ' compile errors.'
    );
  end if;

  execute immediate q'~
    select
      (select count(*) from of_purchase_requests
        where request_no like 'P07T-%')
      +
      (select count(*) from of_purchase_orders
        where po_no like 'P07PO-%')
      +
      (select count(*) from of_goods_receipts
        where receipt_no like 'P07GR-%')
      +
      (select count(*) from of_audit_log
        where (entity_type_code = 'PURCHASE_REQUEST'
               and entity_key like 'P07T-%')
           or (entity_type_code = 'PURCHASE_ORDER'
               and entity_key like 'P07PO-%')
           or (entity_type_code = 'GOODS_RECEIPT'
               and entity_key like 'P07GR-%'))
      from dual
  ~' into l_residue_count;

  if l_residue_count <> 0 then
    raise_application_error(
      -20482,
      'P08 stopped: P07 transaction-test residue count is ' ||
      l_residue_count || '. Complete P07 cleanup and validation first.'
    );
  end if;

  dbms_output.put_line(
    'P08 database preflight passed. Manual P07 evidence gate remains required.'
  );
end;
/

--------------------------------------------------------------------------------
-- 01. OF_APEX_API specification
--------------------------------------------------------------------------------

create or replace package of_apex_api authid definer as
  function current_display_name return varchar2;

  function current_locale_code return varchar2;

  function current_timezone_name return varchar2;

  function current_role_codes return varchar2;

  function handle_error(
    p_error in apex_error.t_error
  ) return apex_error.t_error_result;
end of_apex_api;
/

--------------------------------------------------------------------------------
-- 02. OF_APEX_API body
--------------------------------------------------------------------------------

create or replace package body of_apex_api as
  function current_display_name return varchar2 is
    l_display_name of_app_users.display_name%type;
  begin
    select max(display_name)
      into l_display_name
      from of_app_users
     where id = of_security_api.current_user_id()
       and is_active = 'Y';

    return coalesce(l_display_name, of_security_api.current_username());
  end current_display_name;

  function current_locale_code return varchar2 is
    l_locale_code of_app_users.locale_code%type;
  begin
    select max(locale_code)
      into l_locale_code
      from of_app_users
     where id = of_security_api.current_user_id()
       and is_active = 'Y';

    return coalesce(
      l_locale_code,
      of_util_api.get_setting_text('DEFAULT_LOCALE', 'en')
    );
  end current_locale_code;

  function current_timezone_name return varchar2 is
    l_timezone_name of_app_users.timezone_name%type;
  begin
    select max(timezone_name)
      into l_timezone_name
      from of_app_users
     where id = of_security_api.current_user_id()
       and is_active = 'Y';

    return coalesce(
      l_timezone_name,
      of_util_api.get_setting_text('DEFAULT_TIMEZONE', 'Africa/Cairo')
    );
  end current_timezone_name;

  function current_role_codes return varchar2 is
    l_role_codes varchar2(4000 char);
  begin
    select listagg(r.code, ', ') within group (order by r.code)
      into l_role_codes
      from of_user_roles ur
      join of_roles r
        on r.id = ur.role_id
       and r.is_active = 'Y'
     where ur.user_id = of_security_api.current_user_id()
       and ur.is_active = 'Y';

    return coalesce(l_role_codes, 'NO ACTIVE ROLE');
  end current_role_codes;

  function write_apex_error(
    p_error in apex_error.t_error
  ) return varchar2 is
    pragma autonomous_transaction;
    l_correlation_id varchar2(64 char) := of_util_api.new_correlation_id();
    l_message        varchar2(4000 char);
    l_error_stack    clob;
  begin
    l_message := substr(
      coalesce(p_error.ora_sqlerrm, p_error.message, 'Unhandled APEX error.'),
      1,
      4000
    );

    l_error_stack := to_clob(
      substr(
        'APEX_ERROR_CODE=' ||
        substr(coalesce(p_error.apex_error_code, 'NONE'), 1, 2000) ||
        chr(10) || 'MESSAGE=' ||
        substr(coalesce(p_error.message, 'NONE'), 1, 8000) ||
        chr(10) || 'ADDITIONAL_INFO=' ||
        substr(coalesce(p_error.additional_info, 'NONE'), 1, 8000) ||
        chr(10) || 'ERROR_STATEMENT=' ||
        substr(coalesce(p_error.error_statement, 'NONE'), 1, 8000),
        1,
        32767
      )
    );

    insert into of_error_log (
      correlation_id,
      actor_user_id,
      location_code,
      error_message,
      error_stack,
      backtrace,
      call_stack,
      app_id,
      page_id,
      is_handled
    ) values (
      l_correlation_id,
      of_security_api.current_user_id(),
      'APEX.ERROR_HANDLER',
      l_message,
      l_error_stack,
      to_clob(p_error.error_backtrace),
      to_clob(dbms_utility.format_call_stack),
      of_util_api.current_app_id(),
      of_util_api.current_page_id(),
      'Y'
    );

    commit;
    return l_correlation_id;
  exception
    when others then
      rollback;
      return l_correlation_id;
  end write_apex_error;

  function handle_error(
    p_error in apex_error.t_error
  ) return apex_error.t_error_result is
    l_result         apex_error.t_error_result;
    l_correlation_id varchar2(64 char);
  begin
    l_result := apex_error.init_error_result(p_error => p_error);

    if p_error.ora_sqlcode between -20999 and -20000 then
      l_result.message := apex_error.get_first_ora_error_text(
        p_error => p_error
      );
      l_result.additional_info := null;
    elsif p_error.ora_sqlcode in (-1, -2290, -2291, -2292) then
      l_result.message :=
        'The submitted values conflict with an existing business rule.';
      l_result.additional_info := null;
    elsif p_error.is_internal_error
          and not p_error.is_common_runtime_error then
      l_correlation_id := write_apex_error(p_error);
      l_result.message := of_error_api.user_message(l_correlation_id);
      l_result.additional_info := null;
    elsif p_error.ora_sqlcode is not null then
      l_correlation_id := write_apex_error(p_error);
      l_result.message := of_error_api.user_message(l_correlation_id);
      l_result.additional_info := null;
    end if;

    if l_result.page_item_name is null
       and l_result.column_alias is null
       and not p_error.is_internal_error then
      apex_error.auto_set_associated_item(
        p_error        => p_error,
        p_error_result => l_result
      );
    end if;

    return l_result;
  exception
    when others then
      l_result := apex_error.init_error_result(p_error => p_error);
      l_result.message := 'Something went wrong. Please contact support.';
      l_result.additional_info := null;
      return l_result;
  end handle_error;
end of_apex_api;
/

--------------------------------------------------------------------------------
-- 03. Immediate object-health result
-- Expected: 2 rows, both VALID.
--------------------------------------------------------------------------------

select object_name,
       object_type,
       status
  from user_objects
 where object_name = 'OF_APEX_API'
   and object_type in ('PACKAGE', 'PACKAGE BODY')
 order by object_type;

--------------------------------------------------------------------------------
-- 04. Immediate compile diagnostics
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
-- End P08 support installer. Expected SQL Scripts statements: 5.
--------------------------------------------------------------------------------
