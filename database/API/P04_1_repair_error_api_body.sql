--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P04.1 - OF_ERROR_API Body Compile Repair
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Purpose: Repairs P04 installer revision 1 after ORA-00984 at package-body
--          line 41. SQLERRM was used directly inside an INSERT values list.
-- Safety: Replaces only OF_ERROR_API package body; no table data is changed.
-- Prerequisite: OF_ERROR_API specification and the other P04 packages exist.
--------------------------------------------------------------------------------

create or replace package body of_error_api as
  function log_current_error(
    p_location_code in varchar2,
    p_is_handled    in char default 'Y'
  ) return varchar2 is
    pragma autonomous_transaction;
    l_correlation_id varchar2(64 char) := of_util_api.new_correlation_id();
    l_error_stack    varchar2(4000 char);
    l_backtrace      varchar2(4000 char);
    l_call_stack     varchar2(4000 char);
    l_error_message  varchar2(4000 char);
  begin
    if trim(p_location_code) is null or length(trim(p_location_code)) > 200 then
      rollback;
      return l_correlation_id;
    end if;

    if upper(trim(p_is_handled)) not in ('Y', 'N') then
      rollback;
      return l_correlation_id;
    end if;

    l_error_stack := dbms_utility.format_error_stack;
    l_backtrace := dbms_utility.format_error_backtrace;
    l_call_stack := dbms_utility.format_call_stack;
    l_error_message := substr(
      coalesce(l_error_stack, 'Unhandled database error.'),
      1,
      4000
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
      upper(trim(p_location_code)),
      l_error_message,
      l_error_stack,
      l_backtrace,
      l_call_stack,
      of_util_api.current_app_id(),
      of_util_api.current_page_id(),
      upper(trim(p_is_handled))
    );

    commit;
    return l_correlation_id;
  exception
    when others then
      rollback;
      return l_correlation_id;
  end log_current_error;

  function user_message(
    p_correlation_id in varchar2
  ) return varchar2 is
  begin
    return 'Something went wrong. Reference: ' ||
           substr(trim(p_correlation_id), 1, 64);
  end user_message;
end of_error_api;
/

--------------------------------------------------------------------------------
-- Expected: no rows. Any row means the repair did not compile.
--------------------------------------------------------------------------------

select name,
       type,
       line,
       position,
       text
  from user_errors
 where name = 'OF_ERROR_API'
 order by type, sequence;

--------------------------------------------------------------------------------
-- Expected: 2 rows; PACKAGE and PACKAGE BODY are both VALID.
--------------------------------------------------------------------------------

select object_name,
       object_type,
       status
  from user_objects
 where object_name = 'OF_ERROR_API'
   and object_type in ('PACKAGE', 'PACKAGE BODY')
 order by object_type;

--------------------------------------------------------------------------------
-- End P04.1 repair. Expected SQL Scripts statements: 3.
--------------------------------------------------------------------------------
