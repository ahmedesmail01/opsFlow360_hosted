--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P04 - Security, Audit, Error, and Utility PL/SQL Foundation
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Creates: 4 package specifications, 4 package bodies, 1 audit guard trigger
-- Safety: Fails before DDL unless the P02 tables and P03 views/data exist.
-- Important: Oracle DDL commits. Follow the P04 recovery guide after any error.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 00. Physical prerequisite and collision preflight
--------------------------------------------------------------------------------

declare
  l_table_count      number;
  l_view_count       number;
  l_reference_count  number;
  l_demo_count       number;
  l_collision_count  number;
begin
  select count(*)
    into l_table_count
    from user_tables
   where table_name in (
     'OF_DEPARTMENTS', 'OF_LOCATIONS', 'OF_APP_USERS', 'OF_ROLES',
     'OF_USER_ROLES', 'OF_APP_SETTINGS', 'OF_AUDIT_LOG', 'OF_ERROR_LOG',
     'OF_NOTIFICATIONS', 'OF_PRIORITIES', 'OF_SERVICE_CATEGORIES',
     'OF_SLA_POLICIES', 'OF_TICKETS', 'OF_TICKET_COMMENTS',
     'OF_TICKET_STATUS_HISTORY', 'OF_TICKET_SLA_PAUSES', 'OF_SLA_EVENTS'
   );

  select count(*)
    into l_view_count
    from user_objects
   where object_type = 'VIEW'
     and status = 'VALID'
     and object_name in (
       'OF_V_TICKET_DETAILS', 'OF_V_SLA_QUEUE', 'OF_V_SERVICE_DASHBOARD',
       'OF_V_USER_ACCESS', 'OF_V_TICKET_TIMELINE'
     );

  select count(*)
    into l_collision_count
    from user_objects
   where object_name in (
     'OF_UTIL_API', 'OF_SECURITY_API', 'OF_AUDIT_API', 'OF_ERROR_API',
     'OF_AUDIT_LOG_GUARD_TRG'
   )
     and object_type in ('PACKAGE', 'PACKAGE BODY', 'TRIGGER');

  if l_table_count <> 17 then
    raise_application_error(
      -20040,
      'P04 stopped: expected 17 P02 tables, found ' || l_table_count || '.'
    );
  end if;

  if l_view_count <> 5 then
    raise_application_error(
      -20041,
      'P04 stopped: expected 5 valid P03 views, found ' || l_view_count || '.'
    );
  end if;

  execute immediate
    'select (select count(*) from of_roles where is_active = ''Y'') ' ||
    '     + (select count(*) from of_app_settings) from dual'
    into l_reference_count;

  execute immediate
    'select count(*) from of_tickets where ticket_no like ''TKT-DEMO-%'''
    into l_demo_count;

  if l_reference_count <> 11 then
    raise_application_error(
      -20042,
      'P04 stopped: expected 6 active roles plus 5 settings, found ' ||
      l_reference_count || ' rows.'
    );
  end if;

  if l_demo_count <> 12 then
    raise_application_error(
      -20042,
      'P04 stopped: expected 12 P03 demo tickets, found ' ||
      l_demo_count || '. Run and validate the P03 demo seed first.'
    );
  end if;

  if l_collision_count > 0 then
    raise_application_error(
      -20043,
      'P04 stopped: ' || l_collision_count ||
      ' P04 object(s) already exist. Validate or roll back; do not mix installs.'
    );
  end if;

  dbms_output.put_line(
    'P04 preflight passed: P02/P03 prerequisites exist and no P04 collision exists.'
  );
end;
/

--------------------------------------------------------------------------------
-- 01. OF_UTIL_API
-- Shared normalization, correlation, APEX request context, and typed settings.
--------------------------------------------------------------------------------

create or replace package of_util_api authid definer as
  function normalize_code(
    p_value in varchar2
  ) return varchar2 deterministic;

  function normalize_username(
    p_value in varchar2
  ) return varchar2 deterministic;

  function new_correlation_id return varchar2;

  function current_app_id return number;

  function current_page_id return number;

  function get_setting_text(
    p_setting_code in varchar2,
    p_default      in varchar2 default null
  ) return varchar2;

  function get_setting_number(
    p_setting_code in varchar2,
    p_default      in number default null
  ) return number;

  function get_setting_boolean(
    p_setting_code in varchar2,
    p_default      in boolean default null
  ) return boolean;
end of_util_api;
/

create or replace package body of_util_api as
  function normalize_code(
    p_value in varchar2
  ) return varchar2 deterministic is
  begin
    return upper(trim(p_value));
  end normalize_code;

  function normalize_username(
    p_value in varchar2
  ) return varchar2 deterministic is
  begin
    return upper(trim(p_value));
  end normalize_username;

  function new_correlation_id return varchar2 is
  begin
    return rawtohex(sys_guid());
  end new_correlation_id;

  function context_number(
    p_attribute in varchar2
  ) return number is
    l_value varchar2(4000 char);
  begin
    l_value := sys_context('APEX$SESSION', p_attribute);

    if l_value is null then
      return null;
    end if;

    return to_number(l_value);
  exception
    when value_error then
      return null;
  end context_number;

  function current_app_id return number is
  begin
    return context_number('APP_ID');
  end current_app_id;

  function current_page_id return number is
  begin
    return nv('APP_PAGE_ID');
  exception
    when others then
      return null;
  end current_page_id;

  procedure read_setting(
    p_setting_code in  varchar2,
    p_data_type    out varchar2,
    p_value        out varchar2,
    p_found        out boolean
  ) is
  begin
    select data_type_code,
           dbms_lob.substr(setting_value, 4000, 1)
      into p_data_type,
           p_value
      from of_app_settings
     where setting_code = normalize_code(p_setting_code);

    p_found := true;
  exception
    when no_data_found then
      p_data_type := null;
      p_value := null;
      p_found := false;
  end read_setting;

  function get_setting_text(
    p_setting_code in varchar2,
    p_default      in varchar2 default null
  ) return varchar2 is
    l_data_type varchar2(20 char);
    l_value     varchar2(4000 char);
    l_found     boolean;
  begin
    read_setting(p_setting_code, l_data_type, l_value, l_found);

    if not l_found then
      return p_default;
    end if;

    if l_data_type <> 'TEXT' then
      raise_application_error(
        -20010,
        'Setting ' || normalize_code(p_setting_code) ||
        ' is ' || l_data_type || ', not TEXT.'
      );
    end if;

    return l_value;
  end get_setting_text;

  function get_setting_number(
    p_setting_code in varchar2,
    p_default      in number default null
  ) return number is
    l_data_type varchar2(20 char);
    l_value     varchar2(4000 char);
    l_found     boolean;
  begin
    read_setting(p_setting_code, l_data_type, l_value, l_found);

    if not l_found then
      return p_default;
    end if;

    if l_data_type <> 'NUMBER' then
      raise_application_error(
        -20011,
        'Setting ' || normalize_code(p_setting_code) ||
        ' is ' || l_data_type || ', not NUMBER.'
      );
    end if;

    begin
      return to_number(trim(l_value));
    exception
      when value_error then
        raise_application_error(
          -20012,
          'Setting ' || normalize_code(p_setting_code) ||
          ' does not contain a valid number.'
        );
    end;
  end get_setting_number;

  function get_setting_boolean(
    p_setting_code in varchar2,
    p_default      in boolean default null
  ) return boolean is
    l_data_type varchar2(20 char);
    l_value     varchar2(4000 char);
    l_found     boolean;
  begin
    read_setting(p_setting_code, l_data_type, l_value, l_found);

    if not l_found then
      return p_default;
    end if;

    if l_data_type <> 'BOOLEAN' then
      raise_application_error(
        -20011,
        'Setting ' || normalize_code(p_setting_code) ||
        ' is ' || l_data_type || ', not BOOLEAN.'
      );
    end if;

    case upper(trim(l_value))
      when 'Y'     then return true;
      when 'YES'   then return true;
      when 'TRUE'  then return true;
      when '1'     then return true;
      when 'N'     then return false;
      when 'NO'    then return false;
      when 'FALSE' then return false;
      when '0'     then return false;
      else
        raise_application_error(
          -20013,
          'Setting ' || normalize_code(p_setting_code) ||
          ' does not contain a valid boolean.'
        );
    end case;
  end get_setting_boolean;
end of_util_api;
/

--------------------------------------------------------------------------------
-- 02. OF_SECURITY_API
-- Maps the server-owned APEX identity to an active business user and roles.
--------------------------------------------------------------------------------

create or replace package of_security_api authid definer as
  c_role_employee            constant varchar2(30 char) := 'EMPLOYEE';
  c_role_service_agent       constant varchar2(30 char) := 'SERVICE_AGENT';
  c_role_procurement_officer constant varchar2(30 char) := 'PROCUREMENT_OFFICER';
  c_role_manager             constant varchar2(30 char) := 'MANAGER';
  c_role_operations_admin    constant varchar2(30 char) := 'OPERATIONS_ADMIN';
  c_role_auditor             constant varchar2(30 char) := 'AUDITOR';

  function current_username return varchar2;

  function current_user_id return number;

  function current_department_id return number;

  function is_authenticated return boolean;

  function has_role(
    p_role_code in varchar2
  ) return boolean;

  function is_employee return boolean;
  function is_service_agent return boolean;
  function is_procurement_officer return boolean;
  function is_manager return boolean;
  function is_operations_admin return boolean;
  function is_auditor return boolean;

  procedure assert_authenticated;

  procedure assert_role(
    p_role_code in varchar2
  );

  procedure assert_any_role(
    p_role_codes_csv in varchar2
  );

  function can_view_ticket(
    p_ticket_id in number
  ) return boolean;

  procedure assert_can_view_ticket(
    p_ticket_id in number
  );
end of_security_api;
/

create or replace package body of_security_api as
  function current_username return varchar2 is
    l_username varchar2(255 char);
  begin
    l_username := sys_context('APEX$SESSION', 'APP_USER');

    if l_username is null then
      l_username := sys_context('USERENV', 'SESSION_USER');
    end if;

    return substr(of_util_api.normalize_username(l_username), 1, 255);
  end current_username;

  function current_user_id return number is
    l_user_id  number;
    l_username varchar2(255 char);
  begin
    l_username := current_username();

    if l_username is null or l_username in ('NOBODY', 'APEX_PUBLIC_USER') then
      return null;
    end if;

    select max(id)
      into l_user_id
      from of_app_users
     where upper(trim(username)) = l_username
       and is_active = 'Y';

    return l_user_id;
  end current_user_id;

  function current_department_id return number is
    l_department_id number;
  begin
    select max(department_id)
      into l_department_id
      from of_app_users
     where id = current_user_id()
       and is_active = 'Y';

    return l_department_id;
  end current_department_id;

  function is_authenticated return boolean is
  begin
    return current_user_id() is not null;
  end is_authenticated;

  function has_role(
    p_role_code in varchar2
  ) return boolean is
    l_count number;
  begin
    select count(*)
      into l_count
      from of_user_roles ur
      join of_roles r
        on r.id = ur.role_id
       and r.is_active = 'Y'
     where ur.user_id = current_user_id()
       and ur.is_active = 'Y'
       and r.code = of_util_api.normalize_code(p_role_code);

    return l_count > 0;
  end has_role;

  function is_employee return boolean is
  begin
    return has_role(c_role_employee);
  end is_employee;

  function is_service_agent return boolean is
  begin
    return has_role(c_role_service_agent);
  end is_service_agent;

  function is_procurement_officer return boolean is
  begin
    return has_role(c_role_procurement_officer);
  end is_procurement_officer;

  function is_manager return boolean is
  begin
    return has_role(c_role_manager);
  end is_manager;

  function is_operations_admin return boolean is
  begin
    return has_role(c_role_operations_admin);
  end is_operations_admin;

  function is_auditor return boolean is
  begin
    return has_role(c_role_auditor);
  end is_auditor;

  procedure assert_authenticated is
  begin
    if not is_authenticated then
      raise_application_error(
        -20020,
        'No active OpsFlow 360 user is mapped to the authenticated identity.'
      );
    end if;
  end assert_authenticated;

  procedure assert_role(
    p_role_code in varchar2
  ) is
  begin
    assert_authenticated;

    if not has_role(p_role_code) then
      raise_application_error(
        -20022,
        'The current user is not authorized for role ' ||
        of_util_api.normalize_code(p_role_code) || '.'
      );
    end if;
  end assert_role;

  procedure assert_any_role(
    p_role_codes_csv in varchar2
  ) is
    l_count number;
  begin
    assert_authenticated;

    select count(*)
      into l_count
      from of_user_roles ur
      join of_roles r
        on r.id = ur.role_id
       and r.is_active = 'Y'
     where ur.user_id = current_user_id()
       and ur.is_active = 'Y'
       and instr(
             ',' || upper(replace(p_role_codes_csv, ' ', '')) || ',',
             ',' || r.code || ','
           ) > 0;

    if l_count = 0 then
      raise_application_error(
        -20022,
        'The current user does not hold any required role.'
      );
    end if;
  end assert_any_role;

  function can_view_ticket(
    p_ticket_id in number
  ) return boolean is
    l_user_id       number;
    l_department_id number;
    l_count         number;
    l_is_employee   number := 0;
    l_is_admin      number := 0;
    l_is_auditor    number := 0;
    l_is_manager    number := 0;
    l_is_agent      number := 0;
  begin
    l_user_id := current_user_id();

    if l_user_id is null or p_ticket_id is null then
      return false;
    end if;

    l_department_id := current_department_id();

    if is_employee() then
      l_is_employee := 1;
    end if;

    if is_operations_admin() then
      l_is_admin := 1;
    end if;

    if is_auditor() then
      l_is_auditor := 1;
    end if;

    if is_manager() then
      l_is_manager := 1;
    end if;

    if is_service_agent() then
      l_is_agent := 1;
    end if;

    select count(*)
      into l_count
      from of_tickets t
      join of_service_categories c
        on c.id = t.category_id
     where t.id = p_ticket_id
       and (
         (l_is_employee = 1 and t.requester_user_id = l_user_id)
         or l_is_admin = 1
         or l_is_auditor = 1
         or (
           l_is_manager = 1
           and t.requester_department_id = l_department_id
         )
         or (
           l_is_agent = 1
           and (
             t.assigned_agent_user_id = l_user_id
             or c.owner_department_id = l_department_id
           )
         )
       );

    return l_count > 0;
  end can_view_ticket;

  procedure assert_can_view_ticket(
    p_ticket_id in number
  ) is
  begin
    assert_authenticated;

    if not can_view_ticket(p_ticket_id) then
      raise_application_error(
        -20023,
        'The requested ticket does not exist or is outside the current user scope.'
      );
    end if;
  end assert_can_view_ticket;
end of_security_api;
/

--------------------------------------------------------------------------------
-- 03. OF_AUDIT_API
-- Sanitized, caller-transaction audit writes. This package never commits.
--------------------------------------------------------------------------------

create or replace package of_audit_api authid definer as
  procedure assert_safe_payload(
    p_payload in clob
  );

  function record_event(
    p_action_code      in varchar2,
    p_entity_type_code in varchar2,
    p_entity_id        in number default null,
    p_entity_key       in varchar2 default null,
    p_old_values_json  in clob default null,
    p_new_values_json  in clob default null,
    p_correlation_id   in varchar2 default null
  ) return varchar2;
end of_audit_api;
/

create or replace package body of_audit_api as
  procedure assert_safe_payload(
    p_payload in clob
  ) is
    l_root json_element_t;

    procedure walk_element(
      p_element in json_element_t
    ) is
      l_object    json_object_t;
      l_array     json_array_t;
      l_keys      json_key_list;
      l_child     json_element_t;
      l_key_upper varchar2(4000 char);
    begin
      if p_element is null then
        return;
      end if;

      if p_element.is_object then
        l_object := treat(p_element as json_object_t);
        l_keys := l_object.get_keys;

        if l_keys.count > 0 then
          for i in 1 .. l_keys.count loop
            l_key_upper := upper(trim(l_keys(i)));

            if l_key_upper in (
              'PASSWORD', 'PASSWORD_HASH', 'TOKEN', 'ACCESS_TOKEN',
              'REFRESH_TOKEN', 'SECRET', 'CLIENT_SECRET', 'CREDENTIAL',
              'AUTHORIZATION', 'API_KEY', 'PRIVATE_KEY'
            ) then
              raise_application_error(
                -20014,
                'Audit JSON contains a prohibited sensitive key.'
              );
            end if;

            l_child := l_object.get(l_keys(i));
            walk_element(l_child);
          end loop;
        end if;
      elsif p_element.is_array then
        l_array := treat(p_element as json_array_t);

        if l_array.get_size > 0 then
          for i in 0 .. l_array.get_size - 1 loop
            l_child := l_array.get(i);
            walk_element(l_child);
          end loop;
        end if;
      end if;
    end walk_element;
  begin
    if p_payload is null then
      return;
    end if;

    l_root := json_element_t.parse(p_payload);

    if not l_root.is_object then
      raise_application_error(
        -20014,
        'Audit JSON must be an object when supplied.'
      );
    end if;

    walk_element(l_root);
  exception
    when others then
      if sqlcode = -20014 then
        raise;
      end if;

      raise_application_error(
        -20014,
        'Audit JSON is invalid or cannot be inspected safely.'
      );
  end assert_safe_payload;

  procedure assert_metadata(
    p_action_code      in varchar2,
    p_entity_type_code in varchar2,
    p_entity_key       in varchar2,
    p_correlation_id   in varchar2
  ) is
  begin
    if of_util_api.normalize_code(p_action_code) is null
       or not regexp_like(
         of_util_api.normalize_code(p_action_code),
         '^[A-Z][A-Z0-9_]{0,49}$'
       ) then
      raise_application_error(-20016, 'Invalid audit action code.');
    end if;

    if of_util_api.normalize_code(p_entity_type_code) is null
       or not regexp_like(
         of_util_api.normalize_code(p_entity_type_code),
         '^[A-Z][A-Z0-9_]{0,49}$'
       ) then
      raise_application_error(-20016, 'Invalid audit entity type code.');
    end if;

    if length(trim(p_entity_key)) > 100 then
      raise_application_error(-20016, 'Audit entity key exceeds 100 characters.');
    end if;

    if length(trim(p_correlation_id)) > 64 then
      raise_application_error(-20016, 'Audit correlation ID exceeds 64 characters.');
    end if;
  end assert_metadata;

  function record_event(
    p_action_code      in varchar2,
    p_entity_type_code in varchar2,
    p_entity_id        in number default null,
    p_entity_key       in varchar2 default null,
    p_old_values_json  in clob default null,
    p_new_values_json  in clob default null,
    p_correlation_id   in varchar2 default null
  ) return varchar2 is
    l_correlation_id varchar2(64 char);
  begin
    l_correlation_id := coalesce(
      trim(p_correlation_id),
      of_util_api.new_correlation_id()
    );

    assert_metadata(
      p_action_code,
      p_entity_type_code,
      p_entity_key,
      l_correlation_id
    );
    assert_safe_payload(p_old_values_json);
    assert_safe_payload(p_new_values_json);

    insert into of_audit_log (
      actor_user_id,
      actor_name,
      action_code,
      entity_type_code,
      entity_id,
      entity_key,
      old_values_json,
      new_values_json,
      correlation_id,
      app_id,
      page_id
    ) values (
      of_security_api.current_user_id(),
      of_security_api.current_username(),
      of_util_api.normalize_code(p_action_code),
      of_util_api.normalize_code(p_entity_type_code),
      p_entity_id,
      trim(p_entity_key),
      p_old_values_json,
      p_new_values_json,
      l_correlation_id,
      of_util_api.current_app_id(),
      of_util_api.current_page_id()
    );

    return l_correlation_id;
  end record_event;
end of_audit_api;
/

--------------------------------------------------------------------------------
-- 04. Audit guard
-- INSERT context is server-derived. Existing audit rows cannot be changed.
--------------------------------------------------------------------------------

create or replace trigger of_audit_log_guard_trg
  before insert or update or delete on of_audit_log
  for each row
begin
  if inserting then
    of_audit_api.assert_safe_payload(:new.old_values_json);
    of_audit_api.assert_safe_payload(:new.new_values_json);

    if of_util_api.normalize_code(:new.action_code) is null
       or not regexp_like(
         of_util_api.normalize_code(:new.action_code),
         '^[A-Z][A-Z0-9_]{0,49}$'
       ) then
      raise_application_error(-20016, 'Invalid audit action code.');
    end if;

    if of_util_api.normalize_code(:new.entity_type_code) is null
       or not regexp_like(
         of_util_api.normalize_code(:new.entity_type_code),
         '^[A-Z][A-Z0-9_]{0,49}$'
       ) then
      raise_application_error(-20016, 'Invalid audit entity type code.');
    end if;

    :new.occurred_at := systimestamp;
    :new.actor_user_id := of_security_api.current_user_id();
    :new.actor_name := of_security_api.current_username();
    :new.action_code := of_util_api.normalize_code(:new.action_code);
    :new.entity_type_code := of_util_api.normalize_code(:new.entity_type_code);
    :new.entity_key := trim(:new.entity_key);
    :new.correlation_id := coalesce(
      trim(:new.correlation_id),
      of_util_api.new_correlation_id()
    );
    :new.app_id := of_util_api.current_app_id();
    :new.page_id := of_util_api.current_page_id();

    if length(:new.entity_key) > 100 or length(:new.correlation_id) > 64 then
      raise_application_error(-20016, 'Audit metadata exceeds its allowed length.');
    end if;
  else
    raise_application_error(
      -20015,
      'Audit evidence is immutable: UPDATE and DELETE are not allowed.'
    );
  end if;
end;
/

--------------------------------------------------------------------------------
-- 05. OF_ERROR_API
-- Autonomous technical logging that survives a caller rollback.
--------------------------------------------------------------------------------

create or replace package of_error_api authid definer as
  function log_current_error(
    p_location_code in varchar2,
    p_is_handled    in char default 'Y'
  ) return varchar2;

  function user_message(
    p_correlation_id in varchar2
  ) return varchar2;
end of_error_api;
/

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
      substr(coalesce(l_error_stack, sqlerrm), 1, 4000),
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
-- 06. Immediate object-health result
-- Expected: 9 rows, all VALID; 4 PACKAGE + 4 PACKAGE BODY + 1 TRIGGER.
--------------------------------------------------------------------------------

select object_name,
       object_type,
       status
  from user_objects
 where object_name in (
   'OF_UTIL_API', 'OF_SECURITY_API', 'OF_AUDIT_API', 'OF_ERROR_API',
   'OF_AUDIT_LOG_GUARD_TRG'
 )
   and object_type in ('PACKAGE', 'PACKAGE BODY', 'TRIGGER')
 order by object_name, object_type;

--------------------------------------------------------------------------------
-- End P04 installer. Expected SQL Scripts statements: 11.
--------------------------------------------------------------------------------
