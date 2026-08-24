--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P05 - Ticket Lifecycle API Vertical Slice
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Creates: OF_TICKET_API package specification/body and one history guard trigger
-- Safety: Reports prerequisites before DDL. CREATE OR REPLACE supports repair.
-- Transaction rule: The package uses action savepoints but never COMMITs.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 00. Prerequisite and existing-object observation
--------------------------------------------------------------------------------

declare
  l_table_count     number;
  l_p04_valid_count number;
  l_demo_count      number;
  l_collision_count number;
begin
  select count(*)
    into l_table_count
    from user_tables
   where table_name in (
     'OF_DEPARTMENTS', 'OF_APP_USERS', 'OF_ROLES', 'OF_USER_ROLES',
     'OF_APP_SETTINGS',
     'OF_LOCATIONS', 'OF_PRIORITIES', 'OF_SERVICE_CATEGORIES',
     'OF_SLA_POLICIES', 'OF_TICKETS', 'OF_TICKET_COMMENTS',
     'OF_TICKET_STATUS_HISTORY', 'OF_TICKET_SLA_PAUSES', 'OF_AUDIT_LOG'
   );

  select count(*)
    into l_p04_valid_count
    from user_objects
   where object_name in (
     'OF_UTIL_API', 'OF_SECURITY_API', 'OF_AUDIT_API', 'OF_ERROR_API',
     'OF_AUDIT_LOG_GUARD_TRG'
   )
     and object_type in ('PACKAGE', 'PACKAGE BODY', 'TRIGGER')
     and status = 'VALID';

  execute immediate
    'select count(*) from of_tickets where ticket_no like ''TKT-DEMO-%'''
    into l_demo_count;

  select count(*)
    into l_collision_count
    from user_objects
   where object_name in ('OF_TICKET_API', 'OF_TICKET_HISTORY_GUARD_TRG')
     and object_type in ('PACKAGE', 'PACKAGE BODY', 'TRIGGER');

  if l_table_count <> 14 then
    raise_application_error(
      -20140,
      'P05 stopped: expected 14 required P02 tables, found ' ||
      l_table_count || '.'
    );
  end if;

  if l_p04_valid_count <> 9 then
    raise_application_error(
      -20141,
      'P05 stopped: expected 9 valid P04 code objects, found ' ||
      l_p04_valid_count || '. Complete P04 repair, validation, and tests first.'
    );
  end if;

  if l_demo_count <> 12 then
    raise_application_error(
      -20142,
      'P05 stopped: expected 12 P03 demo tickets, found ' || l_demo_count || '.'
    );
  end if;

  if l_collision_count = 0 then
    dbms_output.put_line('P05 install mode: no existing P05 code objects.');
  else
    dbms_output.put_line(
      'P05 repair mode: ' || l_collision_count ||
      ' existing P05 code object(s) will be replaced in place.'
    );
  end if;

  dbms_output.put_line('P05 prerequisite check passed.');
end;
/

--------------------------------------------------------------------------------
-- 01. Public ticket transaction contract
--------------------------------------------------------------------------------

create or replace package of_ticket_api authid definer as
  procedure create_draft(
    p_category_id       in  number,
    p_priority_id       in  number default null,
    p_location_id       in  number default null,
    p_subject           in  varchar2,
    p_description       in  clob,
    p_source_code       in  varchar2 default 'WEB',
    p_requester_user_id in  number default null,
    p_ticket_id         out number,
    p_ticket_no         out varchar2,
    p_row_version       out number
  );

  procedure edit_draft(
    p_ticket_id           in  number,
    p_expected_row_version in number,
    p_category_id         in  number,
    p_priority_id         in  number default null,
    p_location_id         in  number default null,
    p_subject             in  varchar2,
    p_description         in  clob,
    p_new_row_version     out number
  );

  procedure submit_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_new_row_version      out number
  );

  procedure triage_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_category_id          in  number,
    p_priority_id          in  number default null,
    p_assigned_agent_id    in  number default null,
    p_reason_text          in  varchar2 default null,
    p_new_row_version      out number
  );

  procedure assign_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_assigned_agent_id    in  number,
    p_reason_text          in  varchar2 default null,
    p_new_row_version      out number
  );

  procedure start_work(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_new_row_version      out number
  );

  procedure add_comment(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_visibility_code      in  varchar2,
    p_comment_text         in  clob,
    p_comment_id           out number,
    p_new_row_version      out number
  );

  procedure wait_for_user(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_request_text         in  clob,
    p_new_row_version      out number
  );

  procedure resume_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_reason_text          in  varchar2 default null,
    p_new_row_version      out number
  );

  procedure resolve_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_resolution_summary   in  clob,
    p_new_row_version      out number
  );

  procedure close_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_closure_reason       in  varchar2 default null,
    p_new_row_version      out number
  );

  procedure reject_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_reason_text          in  varchar2,
    p_new_row_version      out number
  );

  procedure cancel_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_reason_text          in  varchar2,
    p_new_row_version      out number
  );

  procedure reopen_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_reason_text          in  varchar2,
    p_new_row_version      out number
  );
end of_ticket_api;
/

--------------------------------------------------------------------------------
-- 02. Ticket lifecycle implementation
--------------------------------------------------------------------------------

create or replace package body of_ticket_api as
  procedure fail(
    p_code    in number,
    p_message in varchar2
  ) is
  begin
    raise_application_error(p_code, p_message);
  end fail;

  procedure assert_text(
    p_value      in varchar2,
    p_label      in varchar2,
    p_max_length in number
  ) is
  begin
    if trim(p_value) is null then
      fail(-20100, p_label || ' is required.');
    end if;

    if length(trim(p_value)) > p_max_length then
      fail(-20100, p_label || ' exceeds ' || p_max_length || ' characters.');
    end if;
  end assert_text;

  procedure assert_clob_text(
    p_value in clob,
    p_label in varchar2
  ) is
    l_probe varchar2(4000 char);
  begin
    if p_value is null then
      fail(-20100, p_label || ' is required.');
    end if;

    l_probe := dbms_lob.substr(p_value, 4000, 1);

    if trim(l_probe) is null then
      fail(-20100, p_label || ' must contain nonblank text.');
    end if;
  end assert_clob_text;

  function actor_id return number is
  begin
    of_security_api.assert_authenticated;
    return of_security_api.current_user_id();
  end actor_id;

  procedure lock_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_ticket               out of_tickets%rowtype
  ) is
    e_resource_busy exception;
    pragma exception_init(e_resource_busy, -54);
  begin
    if p_ticket_id is null or p_expected_row_version is null
       or p_expected_row_version < 1 then
      fail(-20100, 'Ticket ID and expected row version are required.');
    end if;

    -- P04 deliberately combines missing and out-of-scope records so an actor
    -- cannot probe ticket existence. Recheck action-specific authority later.
    of_security_api.assert_can_view_ticket(p_ticket_id);

    select *
      into p_ticket
      from of_tickets
     where id = p_ticket_id
       for update nowait;

    if p_ticket.row_version <> p_expected_row_version then
      fail(
        -20102,
        'Ticket changed since it was loaded. Refresh and try again.'
      );
    end if;
  exception
    when no_data_found then
      fail(-20101, 'Ticket does not exist or is no longer available.');
    when e_resource_busy then
      fail(-20103, 'Ticket is currently being changed by another session.');
  end lock_ticket;

  procedure assert_state(
    p_actual   in varchar2,
    p_expected in varchar2,
    p_action   in varchar2
  ) is
  begin
    if p_actual <> p_expected then
      fail(
        -20104,
        p_action || ' is not allowed while the ticket is ' || p_actual || '.'
      );
    end if;
  end assert_state;

  procedure assert_requester_or_admin(
    p_ticket in of_tickets%rowtype
  ) is
    l_actor_id number;
  begin
    l_actor_id := actor_id();

    if l_actor_id <> p_ticket.requester_user_id
       and not of_security_api.is_operations_admin() then
      fail(-20105, 'Only the requester or an operations administrator may do this.');
    end if;
  end assert_requester_or_admin;

  procedure assert_requester(
    p_ticket in of_tickets%rowtype
  ) is
  begin
    if actor_id() <> p_ticket.requester_user_id then
      fail(-20105, 'Only the ticket requester may do this.');
    end if;
  end assert_requester;

  procedure read_catalog(
    p_category_id          in  number,
    p_priority_id          in  number,
    p_effective_priority_id out number,
    p_owner_department_id  out number,
    p_requires_location    out char
  ) is
    l_default_priority_id number;
    l_count               number;
  begin
    begin
      select default_priority_id,
             owner_department_id,
             requires_location
        into l_default_priority_id,
             p_owner_department_id,
             p_requires_location
        from of_service_categories
       where id = p_category_id
         and is_active = 'Y';
    exception
      when no_data_found then
        fail(-20106, 'Service category is missing or inactive.');
    end;

    p_effective_priority_id := coalesce(p_priority_id, l_default_priority_id);

    select count(*)
      into l_count
      from of_priorities
     where id = p_effective_priority_id
       and is_active = 'Y';

    if l_count <> 1 then
      fail(-20106, 'Priority is missing or inactive.');
    end if;
  end read_catalog;

  procedure assert_location(
    p_location_id      in number,
    p_requires_location in char
  ) is
    l_count number;
  begin
    if p_requires_location = 'Y' and p_location_id is null then
      fail(-20107, 'A location is required for this service category.');
    end if;

    if p_location_id is not null then
      select count(*)
        into l_count
        from of_locations
       where id = p_location_id
         and is_active = 'Y';

      if l_count <> 1 then
        fail(-20106, 'Location is missing or inactive.');
      end if;
    end if;
  end assert_location;

  procedure assert_service_scope(
    p_category_id in number
  ) is
    l_owner_department_id number;
  begin
    of_security_api.assert_authenticated;

    if of_security_api.is_operations_admin() then
      return;
    end if;

    if not of_security_api.is_service_agent() then
      fail(-20105, 'A scoped service-agent role is required.');
    end if;

    select owner_department_id
      into l_owner_department_id
      from of_service_categories
     where id = p_category_id;

    if of_security_api.current_department_id() <> l_owner_department_id then
      fail(-20105, 'Ticket is outside the current service-agent scope.');
    end if;
  end assert_service_scope;

  procedure assert_assigned_actor(
    p_ticket in of_tickets%rowtype
  ) is
  begin
    of_security_api.assert_authenticated;

    if of_security_api.is_operations_admin() then
      return;
    end if;

    if not of_security_api.is_service_agent()
       or p_ticket.assigned_agent_user_id <> of_security_api.current_user_id() then
      fail(-20105, 'The assigned service agent or an administrator is required.');
    end if;
  end assert_assigned_actor;

  procedure assert_valid_agent(
    p_agent_user_id     in number,
    p_owner_department_id in number
  ) is
    l_count number;
  begin
    if p_agent_user_id is null then
      fail(-20108, 'Assigned agent is required.');
    end if;

    select count(*)
      into l_count
      from of_app_users u
      join of_user_roles ur
        on ur.user_id = u.id
       and ur.is_active = 'Y'
      join of_roles r
        on r.id = ur.role_id
       and r.is_active = 'Y'
       and r.code = 'SERVICE_AGENT'
     where u.id = p_agent_user_id
       and u.is_active = 'Y'
       and u.department_id = p_owner_department_id;

    if l_count <> 1 then
      fail(
        -20108,
        'Assigned agent must be an active service agent in the owning department.'
      );
    end if;
  end assert_valid_agent;

  procedure read_sla(
    p_category_id       in  number,
    p_priority_id       in  number,
    p_sla_policy_id     out number,
    p_response_minutes  out number,
    p_resolution_minutes out number,
    p_pause_when_waiting out char
  ) is
  begin
    select id,
           response_minutes,
           resolution_minutes,
           pause_when_waiting_user
      into p_sla_policy_id,
           p_response_minutes,
           p_resolution_minutes,
           p_pause_when_waiting
      from (
        select id,
               response_minutes,
               resolution_minutes,
               pause_when_waiting_user
          from of_sla_policies
         where category_id = p_category_id
           and priority_id = p_priority_id
           and is_active = 'Y'
           and trunc(current_date) between effective_from
                                       and coalesce(effective_to, date '9999-12-31')
         order by effective_from desc, id desc
      )
     where rownum = 1;
  exception
    when no_data_found then
      fail(-20109, 'No active SLA policy matches the selected category and priority.');
  end read_sla;

  function state_json(
    p_status_code in varchar2,
    p_row_version in number,
    p_agent_id    in number
  ) return clob is
    l_json json_object_t := json_object_t();
  begin
    if p_status_code is null then
      l_json.put_null('statusCode');
    else
      l_json.put('statusCode', p_status_code);
    end if;

    l_json.put('rowVersion', p_row_version);

    if p_agent_id is null then
      l_json.put_null('assignedAgentUserId');
    else
      l_json.put('assignedAgentUserId', p_agent_id);
    end if;

    return l_json.to_clob();
  end state_json;

  procedure audit_change(
    p_action_code in varchar2,
    p_ticket_id   in number,
    p_ticket_no   in varchar2,
    p_old_status  in varchar2,
    p_new_status  in varchar2,
    p_old_version in number,
    p_new_version in number,
    p_old_agent   in number,
    p_new_agent   in number,
    p_correlation_id in varchar2
  ) is
    l_correlation_id varchar2(64 char);
  begin
    l_correlation_id := of_audit_api.record_event(
      p_action_code      => p_action_code,
      p_entity_type_code => 'TICKET',
      p_entity_id        => p_ticket_id,
      p_entity_key       => p_ticket_no,
      p_old_values_json  => state_json(p_old_status, p_old_version, p_old_agent),
      p_new_values_json  => state_json(p_new_status, p_new_version, p_new_agent),
      p_correlation_id   => p_correlation_id
    );
  end audit_change;

  procedure record_transition(
    p_action_code    in varchar2,
    p_ticket_id      in number,
    p_ticket_no      in varchar2,
    p_from_status    in varchar2,
    p_to_status      in varchar2,
    p_reason_text    in varchar2,
    p_old_version    in number,
    p_new_version    in number,
    p_old_agent      in number,
    p_new_agent      in number
  ) is
    l_correlation_id varchar2(64 char);
  begin
    l_correlation_id := of_util_api.new_correlation_id();

    insert into of_ticket_status_history (
      ticket_id,
      from_status_code,
      to_status_code,
      changed_at,
      changed_by_user_id,
      changed_by,
      reason_text,
      correlation_id
    ) values (
      p_ticket_id,
      p_from_status,
      p_to_status,
      systimestamp,
      of_security_api.current_user_id(),
      of_security_api.current_username(),
      substr(trim(p_reason_text), 1, 1000),
      l_correlation_id
    );

    audit_change(
      p_action_code,
      p_ticket_id,
      p_ticket_no,
      p_from_status,
      p_to_status,
      p_old_version,
      p_new_version,
      p_old_agent,
      p_new_agent,
      l_correlation_id
    );
  end record_transition;

  function elapsed_minutes(
    p_started_at in timestamp with local time zone,
    p_ended_at   in timestamp with local time zone
  ) return number is
    l_elapsed interval day(9) to second;
  begin
    l_elapsed := p_ended_at - p_started_at;

    return greatest(
      0,
      floor(
        extract(day from l_elapsed) * 1440
        + extract(hour from l_elapsed) * 60
        + extract(minute from l_elapsed)
        + extract(second from l_elapsed) / 60
      )
    );
  end elapsed_minutes;

  procedure end_active_pause(
    p_ticket_id     in  number,
    p_actor_id      in  number,
    p_ended_at      in  timestamp with local time zone,
    p_duration_minutes out number
  ) is
    l_pause_id   number;
    l_started_at timestamp with local time zone;
  begin
    p_duration_minutes := 0;

    begin
      select id,
             started_at
        into l_pause_id,
             l_started_at
        from of_ticket_sla_pauses
       where ticket_id = p_ticket_id
         and ended_at is null
         for update;
    exception
      when no_data_found then
        return;
    end;

    p_duration_minutes := elapsed_minutes(l_started_at, p_ended_at);

    update of_ticket_sla_pauses
       set ended_at = p_ended_at,
           duration_minutes = p_duration_minutes,
           ended_by_user_id = p_actor_id
     where id = l_pause_id;
  end end_active_pause;

  procedure create_draft(
    p_category_id       in  number,
    p_priority_id       in  number default null,
    p_location_id       in  number default null,
    p_subject           in  varchar2,
    p_description       in  clob,
    p_source_code       in  varchar2 default 'WEB',
    p_requester_user_id in  number default null,
    p_ticket_id         out number,
    p_ticket_no         out varchar2,
    p_row_version       out number
  ) is
    l_actor_id            number;
    l_requester_id        number;
    l_requester_dept_id   number;
    l_priority_id         number;
    l_owner_department_id number;
    l_requires_location   char(1 char);
    l_prefix              varchar2(10 char);
    l_source_code         varchar2(20 char);
  begin
    savepoint of_ticket_api_action;
    p_ticket_id := null;
    p_ticket_no := null;
    p_row_version := null;

    l_actor_id := actor_id();
    assert_text(p_subject, 'Subject', 200);
    assert_clob_text(p_description, 'Description');

    l_source_code := of_util_api.normalize_code(p_source_code);
    if l_source_code not in ('WEB', 'REST') then
      fail(-20100, 'Source must be WEB or REST.');
    end if;

    l_requester_id := coalesce(p_requester_user_id, l_actor_id);

    if l_requester_id <> l_actor_id
       and not of_security_api.is_operations_admin() then
      fail(-20105, 'Only an operations administrator may create for another user.');
    end if;

    begin
      select department_id
        into l_requester_dept_id
        from of_app_users
       where id = l_requester_id
         and is_active = 'Y';
    exception
      when no_data_found then
        fail(-20106, 'Requester is missing or inactive.');
    end;

    if l_requester_dept_id is null then
      fail(-20106, 'Requester must belong to an active business department.');
    end if;

    read_catalog(
      p_category_id,
      p_priority_id,
      l_priority_id,
      l_owner_department_id,
      l_requires_location
    );
    assert_location(p_location_id, 'N');

    l_prefix := substr(
      of_util_api.normalize_code(
        of_util_api.get_setting_text('TICKET_PREFIX', 'TKT')
      ),
      1,
      10
    );

    if l_prefix is null or not regexp_like(l_prefix, '^[A-Z][A-Z0-9_]{0,9}$') then
      fail(-20100, 'TICKET_PREFIX setting is invalid.');
    end if;

    p_ticket_no := l_prefix || '-' || to_char(systimestamp, 'YYYYMMDD') || '-' ||
                   substr(of_util_api.new_correlation_id(), 1, 8);

    insert into of_tickets (
      ticket_no,
      requester_user_id,
      requester_department_id,
      category_id,
      priority_id,
      location_id,
      status_code,
      source_code,
      subject,
      description,
      row_version,
      created_by,
      updated_by
    ) values (
      p_ticket_no,
      l_requester_id,
      l_requester_dept_id,
      p_category_id,
      l_priority_id,
      p_location_id,
      'DRAFT',
      l_source_code,
      trim(p_subject),
      p_description,
      1,
      of_security_api.current_username(),
      of_security_api.current_username()
    ) returning id, row_version into p_ticket_id, p_row_version;

    record_transition(
      'TICKET_CREATE',
      p_ticket_id,
      p_ticket_no,
      null,
      'DRAFT',
      'Draft created.',
      0,
      p_row_version,
      null,
      null
    );
  exception
    when others then
      rollback to of_ticket_api_action;
      p_ticket_id := null;
      p_ticket_no := null;
      p_row_version := null;
      raise;
  end create_draft;

  procedure edit_draft(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_category_id          in  number,
    p_priority_id          in  number default null,
    p_location_id          in  number default null,
    p_subject              in  varchar2,
    p_description          in  clob,
    p_new_row_version      out number
  ) is
    l_ticket              of_tickets%rowtype;
    l_priority_id         number;
    l_owner_department_id number;
    l_requires_location   char(1 char);
    l_correlation_id      varchar2(64 char);
  begin
    savepoint of_ticket_api_action;
    p_new_row_version := null;
    lock_ticket(p_ticket_id, p_expected_row_version, l_ticket);
    assert_state(l_ticket.status_code, 'DRAFT', 'Edit draft');
    assert_requester_or_admin(l_ticket);
    assert_text(p_subject, 'Subject', 200);
    assert_clob_text(p_description, 'Description');

    read_catalog(
      p_category_id,
      p_priority_id,
      l_priority_id,
      l_owner_department_id,
      l_requires_location
    );
    assert_location(p_location_id, 'N');

    update of_tickets
       set category_id = p_category_id,
           priority_id = l_priority_id,
           location_id = p_location_id,
           subject = trim(p_subject),
           description = p_description,
           row_version = row_version + 1,
           updated_at = systimestamp,
           updated_by = of_security_api.current_username()
     where id = p_ticket_id
    returning row_version into p_new_row_version;

    l_correlation_id := of_util_api.new_correlation_id();
    audit_change(
      'TICKET_EDIT', p_ticket_id, l_ticket.ticket_no,
      'DRAFT', 'DRAFT', l_ticket.row_version, p_new_row_version,
      l_ticket.assigned_agent_user_id, l_ticket.assigned_agent_user_id,
      l_correlation_id
    );
  exception
    when others then
      rollback to of_ticket_api_action;
      p_new_row_version := null;
      raise;
  end edit_draft;

  procedure submit_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_new_row_version      out number
  ) is
    l_ticket               of_tickets%rowtype;
    l_priority_id          number;
    l_owner_department_id  number;
    l_requires_location    char(1 char);
    l_sla_policy_id        number;
    l_response_minutes     number;
    l_resolution_minutes   number;
    l_pause_when_waiting    char(1 char);
    l_requester_dept_id    number;
    l_now                  timestamp with local time zone := systimestamp;
  begin
    savepoint of_ticket_api_action;
    p_new_row_version := null;
    lock_ticket(p_ticket_id, p_expected_row_version, l_ticket);
    assert_state(l_ticket.status_code, 'DRAFT', 'Submit');
    assert_requester(l_ticket);

    assert_text(l_ticket.subject, 'Subject', 200);
    assert_clob_text(l_ticket.description, 'Description');

    begin
      select department_id
        into l_requester_dept_id
        from of_app_users
       where id = l_ticket.requester_user_id
         and is_active = 'Y';
    exception
      when no_data_found then
        fail(-20106, 'Requester is missing or inactive.');
    end;

    read_catalog(
      l_ticket.category_id,
      l_ticket.priority_id,
      l_priority_id,
      l_owner_department_id,
      l_requires_location
    );
    assert_location(l_ticket.location_id, l_requires_location);
    read_sla(
      l_ticket.category_id,
      l_priority_id,
      l_sla_policy_id,
      l_response_minutes,
      l_resolution_minutes,
      l_pause_when_waiting
    );

    update of_tickets
       set requester_department_id = l_requester_dept_id,
           priority_id = l_priority_id,
           sla_policy_id = l_sla_policy_id,
           status_code = 'SUBMITTED',
           submitted_at = l_now,
           response_due_at = l_now + numtodsinterval(l_response_minutes, 'MINUTE'),
           resolution_due_at = l_now + numtodsinterval(l_resolution_minutes, 'MINUTE'),
           row_version = row_version + 1,
           updated_at = l_now,
           updated_by = of_security_api.current_username()
     where id = p_ticket_id
    returning row_version into p_new_row_version;

    record_transition(
      'TICKET_SUBMIT', p_ticket_id, l_ticket.ticket_no,
      'DRAFT', 'SUBMITTED', 'Requester submitted the ticket.',
      l_ticket.row_version, p_new_row_version,
      l_ticket.assigned_agent_user_id, l_ticket.assigned_agent_user_id
    );
  exception
    when others then
      rollback to of_ticket_api_action;
      p_new_row_version := null;
      raise;
  end submit_ticket;

  procedure triage_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_category_id          in  number,
    p_priority_id          in  number default null,
    p_assigned_agent_id    in  number default null,
    p_reason_text          in  varchar2 default null,
    p_new_row_version      out number
  ) is
    l_ticket               of_tickets%rowtype;
    l_priority_id          number;
    l_owner_department_id  number;
    l_requires_location    char(1 char);
    l_sla_policy_id        number;
    l_response_minutes     number;
    l_resolution_minutes   number;
    l_pause_when_waiting    char(1 char);
    l_reason               varchar2(1000 char);
    l_now                  timestamp with local time zone := systimestamp;
  begin
    savepoint of_ticket_api_action;
    p_new_row_version := null;
    lock_ticket(p_ticket_id, p_expected_row_version, l_ticket);
    assert_state(l_ticket.status_code, 'SUBMITTED', 'Triage');
    assert_service_scope(l_ticket.category_id);

    read_catalog(
      p_category_id,
      p_priority_id,
      l_priority_id,
      l_owner_department_id,
      l_requires_location
    );
    assert_location(l_ticket.location_id, l_requires_location);

    if not of_security_api.is_operations_admin()
       and of_security_api.current_department_id() <> l_owner_department_id then
      fail(-20105, 'A service agent cannot triage into another department scope.');
    end if;

    if p_assigned_agent_id is not null then
      assert_valid_agent(p_assigned_agent_id, l_owner_department_id);
    end if;

    read_sla(
      p_category_id,
      l_priority_id,
      l_sla_policy_id,
      l_response_minutes,
      l_resolution_minutes,
      l_pause_when_waiting
    );

    l_reason := coalesce(substr(trim(p_reason_text), 1, 1000), 'Ticket triaged.');

    update of_tickets
       set category_id = p_category_id,
           priority_id = l_priority_id,
           sla_policy_id = l_sla_policy_id,
           assigned_agent_user_id = p_assigned_agent_id,
           status_code = 'TRIAGED',
           triaged_at = coalesce(triaged_at, l_now),
           response_due_at = submitted_at +
             numtodsinterval(l_response_minutes, 'MINUTE'),
           resolution_due_at = submitted_at +
             numtodsinterval(l_resolution_minutes, 'MINUTE'),
           row_version = row_version + 1,
           updated_at = l_now,
           updated_by = of_security_api.current_username()
     where id = p_ticket_id
    returning row_version into p_new_row_version;

    record_transition(
      'TICKET_TRIAGE', p_ticket_id, l_ticket.ticket_no,
      'SUBMITTED', 'TRIAGED', l_reason,
      l_ticket.row_version, p_new_row_version,
      l_ticket.assigned_agent_user_id, p_assigned_agent_id
    );
  exception
    when others then
      rollback to of_ticket_api_action;
      p_new_row_version := null;
      raise;
  end triage_ticket;

  procedure assign_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_assigned_agent_id    in  number,
    p_reason_text          in  varchar2 default null,
    p_new_row_version      out number
  ) is
    l_ticket              of_tickets%rowtype;
    l_priority_id         number;
    l_owner_department_id number;
    l_requires_location   char(1 char);
    l_correlation_id      varchar2(64 char);
  begin
    savepoint of_ticket_api_action;
    p_new_row_version := null;
    lock_ticket(p_ticket_id, p_expected_row_version, l_ticket);
    assert_state(l_ticket.status_code, 'TRIAGED', 'Assign');
    assert_service_scope(l_ticket.category_id);

    read_catalog(
      l_ticket.category_id,
      l_ticket.priority_id,
      l_priority_id,
      l_owner_department_id,
      l_requires_location
    );
    assert_valid_agent(p_assigned_agent_id, l_owner_department_id);

    update of_tickets
       set assigned_agent_user_id = p_assigned_agent_id,
           row_version = row_version + 1,
           updated_at = systimestamp,
           updated_by = of_security_api.current_username()
     where id = p_ticket_id
    returning row_version into p_new_row_version;

    l_correlation_id := of_util_api.new_correlation_id();
    audit_change(
      'TICKET_ASSIGN', p_ticket_id, l_ticket.ticket_no,
      'TRIAGED', 'TRIAGED', l_ticket.row_version, p_new_row_version,
      l_ticket.assigned_agent_user_id, p_assigned_agent_id,
      l_correlation_id
    );
  exception
    when others then
      rollback to of_ticket_api_action;
      p_new_row_version := null;
      raise;
  end assign_ticket;

  procedure start_work(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_new_row_version      out number
  ) is
    l_ticket of_tickets%rowtype;
  begin
    savepoint of_ticket_api_action;
    p_new_row_version := null;
    lock_ticket(p_ticket_id, p_expected_row_version, l_ticket);
    assert_state(l_ticket.status_code, 'TRIAGED', 'Start work');

    if l_ticket.assigned_agent_user_id is null then
      fail(-20108, 'Assign an active service agent before starting work.');
    end if;

    assert_assigned_actor(l_ticket);

    update of_tickets
       set status_code = 'IN_PROGRESS',
           row_version = row_version + 1,
           updated_at = systimestamp,
           updated_by = of_security_api.current_username()
     where id = p_ticket_id
    returning row_version into p_new_row_version;

    record_transition(
      'TICKET_START', p_ticket_id, l_ticket.ticket_no,
      'TRIAGED', 'IN_PROGRESS', 'Assigned agent started work.',
      l_ticket.row_version, p_new_row_version,
      l_ticket.assigned_agent_user_id, l_ticket.assigned_agent_user_id
    );
  exception
    when others then
      rollback to of_ticket_api_action;
      p_new_row_version := null;
      raise;
  end start_work;

  procedure add_comment(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_visibility_code      in  varchar2,
    p_comment_text         in  clob,
    p_comment_id           out number,
    p_new_row_version      out number
  ) is
    l_ticket          of_tickets%rowtype;
    l_visibility      varchar2(20 char);
    l_is_service_actor boolean;
    l_correlation_id  varchar2(64 char);
    l_now             timestamp with local time zone := systimestamp;
  begin
    savepoint of_ticket_api_action;
    p_comment_id := null;
    p_new_row_version := null;
    lock_ticket(p_ticket_id, p_expected_row_version, l_ticket);
    of_security_api.assert_can_view_ticket(p_ticket_id);
    assert_clob_text(p_comment_text, 'Comment');

    if l_ticket.status_code in ('CLOSED', 'REJECTED', 'CANCELLED') then
      fail(-20104, 'Comments cannot be added to a terminal ticket.');
    end if;

    l_visibility := of_util_api.normalize_code(p_visibility_code);
    if l_visibility not in ('PUBLIC', 'INTERNAL') then
      fail(-20100, 'Comment visibility must be PUBLIC or INTERNAL.');
    end if;

    l_is_service_actor := of_security_api.is_service_agent()
                          or of_security_api.is_operations_admin();

    if l_visibility = 'INTERNAL' then
      assert_service_scope(l_ticket.category_id);
    elsif actor_id() <> l_ticket.requester_user_id and not l_is_service_actor then
      fail(-20105, 'Only the requester or a scoped service actor may comment.');
    elsif actor_id() <> l_ticket.requester_user_id then
      assert_service_scope(l_ticket.category_id);
    end if;

    insert into of_ticket_comments (
      ticket_id,
      author_user_id,
      visibility_code,
      comment_text,
      is_system_generated,
      created_by,
      updated_by
    ) values (
      p_ticket_id,
      of_security_api.current_user_id(),
      l_visibility,
      p_comment_text,
      'N',
      of_security_api.current_username(),
      of_security_api.current_username()
    ) returning id into p_comment_id;

    update of_tickets
       set first_responded_at = case
             when first_responded_at is null
              and l_visibility = 'PUBLIC'
              and l_is_service_actor
             then l_now
             else first_responded_at
           end,
           row_version = row_version + 1,
           updated_at = l_now,
           updated_by = of_security_api.current_username()
     where id = p_ticket_id
    returning row_version into p_new_row_version;

    l_correlation_id := of_util_api.new_correlation_id();
    audit_change(
      'TICKET_COMMENT', p_ticket_id, l_ticket.ticket_no,
      l_ticket.status_code, l_ticket.status_code,
      l_ticket.row_version, p_new_row_version,
      l_ticket.assigned_agent_user_id, l_ticket.assigned_agent_user_id,
      l_correlation_id
    );
  exception
    when others then
      rollback to of_ticket_api_action;
      p_comment_id := null;
      p_new_row_version := null;
      raise;
  end add_comment;

  procedure wait_for_user(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_request_text         in  clob,
    p_new_row_version      out number
  ) is
    l_ticket            of_tickets%rowtype;
    l_pause_when_waiting char(1 char);
    l_comment_id        number;
    l_now               timestamp with local time zone := systimestamp;
  begin
    savepoint of_ticket_api_action;
    p_new_row_version := null;
    lock_ticket(p_ticket_id, p_expected_row_version, l_ticket);
    assert_state(l_ticket.status_code, 'IN_PROGRESS', 'Wait for user');
    assert_assigned_actor(l_ticket);
    assert_clob_text(p_request_text, 'Request for information');

    select pause_when_waiting_user
      into l_pause_when_waiting
      from of_sla_policies
     where id = l_ticket.sla_policy_id;

    insert into of_ticket_comments (
      ticket_id, author_user_id, visibility_code, comment_text,
      is_system_generated, created_by, updated_by
    ) values (
      p_ticket_id, of_security_api.current_user_id(), 'PUBLIC', p_request_text,
      'N', of_security_api.current_username(), of_security_api.current_username()
    ) returning id into l_comment_id;

    if l_pause_when_waiting = 'Y' then
      insert into of_ticket_sla_pauses (
        ticket_id, started_at, reason_code, started_by_user_id
      ) values (
        p_ticket_id, l_now, 'WAITING_USER', of_security_api.current_user_id()
      );
    end if;

    update of_tickets
       set status_code = 'WAITING_USER',
           waiting_started_at = l_now,
           first_responded_at = coalesce(first_responded_at, l_now),
           row_version = row_version + 1,
           updated_at = l_now,
           updated_by = of_security_api.current_username()
     where id = p_ticket_id
    returning row_version into p_new_row_version;

    record_transition(
      'TICKET_WAIT', p_ticket_id, l_ticket.ticket_no,
      'IN_PROGRESS', 'WAITING_USER', 'Agent requested requester information.',
      l_ticket.row_version, p_new_row_version,
      l_ticket.assigned_agent_user_id, l_ticket.assigned_agent_user_id
    );
  exception
    when others then
      rollback to of_ticket_api_action;
      p_new_row_version := null;
      raise;
  end wait_for_user;

  procedure resume_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_reason_text          in  varchar2 default null,
    p_new_row_version      out number
  ) is
    l_ticket          of_tickets%rowtype;
    l_duration_minutes number;
    l_now             timestamp with local time zone := systimestamp;
    l_reason          varchar2(1000 char);
  begin
    savepoint of_ticket_api_action;
    p_new_row_version := null;
    lock_ticket(p_ticket_id, p_expected_row_version, l_ticket);
    assert_state(l_ticket.status_code, 'WAITING_USER', 'Resume');
    assert_assigned_actor(l_ticket);

    end_active_pause(p_ticket_id, actor_id(), l_now, l_duration_minutes);
    l_reason := coalesce(substr(trim(p_reason_text), 1, 1000), 'Requester information received.');

    update of_tickets
       set status_code = 'IN_PROGRESS',
           waiting_started_at = null,
           resolution_due_at = resolution_due_at +
             numtodsinterval(l_duration_minutes, 'MINUTE'),
           row_version = row_version + 1,
           updated_at = l_now,
           updated_by = of_security_api.current_username()
     where id = p_ticket_id
    returning row_version into p_new_row_version;

    record_transition(
      'TICKET_RESUME', p_ticket_id, l_ticket.ticket_no,
      'WAITING_USER', 'IN_PROGRESS', l_reason,
      l_ticket.row_version, p_new_row_version,
      l_ticket.assigned_agent_user_id, l_ticket.assigned_agent_user_id
    );
  exception
    when others then
      rollback to of_ticket_api_action;
      p_new_row_version := null;
      raise;
  end resume_ticket;

  procedure resolve_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_resolution_summary   in  clob,
    p_new_row_version      out number
  ) is
    l_ticket          of_tickets%rowtype;
    l_duration_minutes number := 0;
    l_now             timestamp with local time zone := systimestamp;
  begin
    savepoint of_ticket_api_action;
    p_new_row_version := null;
    lock_ticket(p_ticket_id, p_expected_row_version, l_ticket);

    if l_ticket.status_code not in ('IN_PROGRESS', 'WAITING_USER') then
      fail(-20104, 'Resolve is allowed only from IN_PROGRESS or WAITING_USER.');
    end if;

    assert_assigned_actor(l_ticket);
    assert_clob_text(p_resolution_summary, 'Resolution summary');

    if l_ticket.status_code = 'WAITING_USER' then
      end_active_pause(p_ticket_id, actor_id(), l_now, l_duration_minutes);
    end if;

    update of_tickets
       set status_code = 'RESOLVED',
           waiting_started_at = null,
           resolution_due_at = resolution_due_at +
             numtodsinterval(l_duration_minutes, 'MINUTE'),
           resolved_at = l_now,
           first_responded_at = coalesce(first_responded_at, l_now),
           resolution_summary = p_resolution_summary,
           closure_reason = null,
           row_version = row_version + 1,
           updated_at = l_now,
           updated_by = of_security_api.current_username()
     where id = p_ticket_id
    returning row_version into p_new_row_version;

    record_transition(
      'TICKET_RESOLVE', p_ticket_id, l_ticket.ticket_no,
      l_ticket.status_code, 'RESOLVED', 'Agent resolved the ticket.',
      l_ticket.row_version, p_new_row_version,
      l_ticket.assigned_agent_user_id, l_ticket.assigned_agent_user_id
    );
  exception
    when others then
      rollback to of_ticket_api_action;
      p_new_row_version := null;
      raise;
  end resolve_ticket;

  procedure close_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_closure_reason       in  varchar2 default null,
    p_new_row_version      out number
  ) is
    l_ticket of_tickets%rowtype;
    l_reason varchar2(1000 char);
  begin
    savepoint of_ticket_api_action;
    p_new_row_version := null;
    lock_ticket(p_ticket_id, p_expected_row_version, l_ticket);
    assert_state(l_ticket.status_code, 'RESOLVED', 'Close');
    assert_requester_or_admin(l_ticket);

    if p_closure_reason is not null then
      assert_text(p_closure_reason, 'Closure reason', 1000);
    end if;
    l_reason := coalesce(substr(trim(p_closure_reason), 1, 1000), 'Resolution accepted.');

    update of_tickets
       set status_code = 'CLOSED',
           closed_at = systimestamp,
           closure_reason = l_reason,
           row_version = row_version + 1,
           updated_at = systimestamp,
           updated_by = of_security_api.current_username()
     where id = p_ticket_id
    returning row_version into p_new_row_version;

    record_transition(
      'TICKET_CLOSE', p_ticket_id, l_ticket.ticket_no,
      'RESOLVED', 'CLOSED', l_reason,
      l_ticket.row_version, p_new_row_version,
      l_ticket.assigned_agent_user_id, l_ticket.assigned_agent_user_id
    );
  exception
    when others then
      rollback to of_ticket_api_action;
      p_new_row_version := null;
      raise;
  end close_ticket;

  procedure reject_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_reason_text          in  varchar2,
    p_new_row_version      out number
  ) is
    l_ticket of_tickets%rowtype;
  begin
    savepoint of_ticket_api_action;
    p_new_row_version := null;
    lock_ticket(p_ticket_id, p_expected_row_version, l_ticket);

    if l_ticket.status_code not in ('SUBMITTED', 'TRIAGED') then
      fail(-20104, 'Reject is allowed only from SUBMITTED or TRIAGED.');
    end if;

    assert_service_scope(l_ticket.category_id);
    assert_text(p_reason_text, 'Rejection reason', 1000);

    update of_tickets
       set status_code = 'REJECTED',
           closure_reason = trim(p_reason_text),
           row_version = row_version + 1,
           updated_at = systimestamp,
           updated_by = of_security_api.current_username()
     where id = p_ticket_id
    returning row_version into p_new_row_version;

    record_transition(
      'TICKET_REJECT', p_ticket_id, l_ticket.ticket_no,
      l_ticket.status_code, 'REJECTED', trim(p_reason_text),
      l_ticket.row_version, p_new_row_version,
      l_ticket.assigned_agent_user_id, l_ticket.assigned_agent_user_id
    );
  exception
    when others then
      rollback to of_ticket_api_action;
      p_new_row_version := null;
      raise;
  end reject_ticket;

  procedure cancel_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_reason_text          in  varchar2,
    p_new_row_version      out number
  ) is
    l_ticket          of_tickets%rowtype;
    l_duration_minutes number := 0;
    l_actor_id         number;
  begin
    savepoint of_ticket_api_action;
    p_new_row_version := null;
    lock_ticket(p_ticket_id, p_expected_row_version, l_ticket);
    l_actor_id := actor_id();
    assert_text(p_reason_text, 'Cancellation reason', 1000);

    if l_ticket.status_code = 'DRAFT' then
      assert_requester(l_ticket);
    elsif l_ticket.status_code = 'SUBMITTED' then
      assert_requester_or_admin(l_ticket);
    elsif l_ticket.status_code in ('TRIAGED', 'IN_PROGRESS', 'WAITING_USER') then
      if not of_security_api.is_operations_admin() then
        fail(-20105, 'Only an operations administrator may cancel after triage.');
      end if;
    else
      fail(-20104, 'Cancel is not allowed while the ticket is ' || l_ticket.status_code || '.');
    end if;

    if l_ticket.status_code = 'WAITING_USER' then
      end_active_pause(p_ticket_id, l_actor_id, systimestamp, l_duration_minutes);
    end if;

    update of_tickets
       set status_code = 'CANCELLED',
           waiting_started_at = null,
           cancelled_at = systimestamp,
           closure_reason = trim(p_reason_text),
           row_version = row_version + 1,
           updated_at = systimestamp,
           updated_by = of_security_api.current_username()
     where id = p_ticket_id
    returning row_version into p_new_row_version;

    record_transition(
      'TICKET_CANCEL', p_ticket_id, l_ticket.ticket_no,
      l_ticket.status_code, 'CANCELLED', trim(p_reason_text),
      l_ticket.row_version, p_new_row_version,
      l_ticket.assigned_agent_user_id, l_ticket.assigned_agent_user_id
    );
  exception
    when others then
      rollback to of_ticket_api_action;
      p_new_row_version := null;
      raise;
  end cancel_ticket;

  procedure reopen_ticket(
    p_ticket_id            in  number,
    p_expected_row_version in  number,
    p_reason_text          in  varchar2,
    p_new_row_version      out number
  ) is
    l_ticket            of_tickets%rowtype;
    l_reopen_days       number;
    l_resolution_minutes number;
    l_now               timestamp with local time zone := systimestamp;
  begin
    savepoint of_ticket_api_action;
    p_new_row_version := null;
    lock_ticket(p_ticket_id, p_expected_row_version, l_ticket);
    assert_state(l_ticket.status_code, 'RESOLVED', 'Reopen');
    assert_requester_or_admin(l_ticket);
    assert_text(p_reason_text, 'Reopen reason', 1000);

    l_reopen_days := of_util_api.get_setting_number('TICKET_REOPEN_DAYS', 7);
    if l_reopen_days <= 0 then
      fail(-20100, 'TICKET_REOPEN_DAYS must be greater than zero.');
    end if;

    if not of_security_api.is_operations_admin()
       and l_now > l_ticket.resolved_at + numtodsinterval(l_reopen_days, 'DAY') then
      fail(-20111, 'The requester reopen window has expired.');
    end if;

    select resolution_minutes
      into l_resolution_minutes
      from of_sla_policies
     where id = l_ticket.sla_policy_id;

    update of_tickets
       set status_code = 'IN_PROGRESS',
           resolved_at = null,
           resolution_summary = null,
           closure_reason = null,
           resolution_due_at = l_now +
             numtodsinterval(l_resolution_minutes, 'MINUTE'),
           row_version = row_version + 1,
           updated_at = l_now,
           updated_by = of_security_api.current_username()
     where id = p_ticket_id
    returning row_version into p_new_row_version;

    record_transition(
      'TICKET_REOPEN', p_ticket_id, l_ticket.ticket_no,
      'RESOLVED', 'IN_PROGRESS', trim(p_reason_text),
      l_ticket.row_version, p_new_row_version,
      l_ticket.assigned_agent_user_id, l_ticket.assigned_agent_user_id
    );
  exception
    when others then
      rollback to of_ticket_api_action;
      p_new_row_version := null;
      raise;
  end reopen_ticket;
end of_ticket_api;
/

--------------------------------------------------------------------------------
-- 03. Status-history immutability guard
-- Inserts remain package-owned by convention. UPDATE and DELETE are blocked.
--------------------------------------------------------------------------------

create or replace trigger of_ticket_history_guard_trg
  before update or delete on of_ticket_status_history
begin
  raise_application_error(
    -20120,
    'Ticket status history is immutable; update and delete are not allowed.'
  );
end;
/

--------------------------------------------------------------------------------
-- 04. Installation result
-- Expected: PACKAGE=1, PACKAGE BODY=1, TRIGGER=1; every object VALID.
--------------------------------------------------------------------------------

select object_name,
       object_type,
       status
  from user_objects
 where object_name in ('OF_TICKET_API', 'OF_TICKET_HISTORY_GUARD_TRG')
 order by object_name, object_type;

--------------------------------------------------------------------------------
-- End P05 installer. Expected SQL Scripts statements: 5.
--------------------------------------------------------------------------------
