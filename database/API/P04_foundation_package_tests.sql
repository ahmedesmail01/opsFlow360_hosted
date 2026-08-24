--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P04 - Foundation Package Tests
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Safety: Business/audit test DML is rolled back. The autonomous error row is
--         explicitly deleted and committed after it is verified.
-- Expected final DBMS_OUTPUT: P04 TEST SUITE: PASS
--------------------------------------------------------------------------------

declare
  l_username          varchar2(255 char);
  l_user_id           number;
  l_department_id     number;
  l_location_id       number;
  l_employee_role_id  number;
  l_ticket_id         number;
  l_other_ticket_id   number;
  l_category_id       number;
  l_priority_id       number;
  l_ticket_no         varchar2(30 char);
  l_correlation_id    varchar2(64 char);
  l_direct_audit_id   number;
  l_actual_number     number;
  l_actual_text       varchar2(4000 char);
  l_actual_boolean    boolean;
  l_error_correlation varchar2(64 char);

  procedure pass(
    p_label in varchar2
  ) is
  begin
    dbms_output.put_line('PASS - ' || p_label);
  end pass;

  procedure fail(
    p_label in varchar2
  ) is
  begin
    raise_application_error(-20990, p_label);
  end fail;

  procedure assert_true(
    p_label     in varchar2,
    p_condition in boolean
  ) is
  begin
    if p_condition then
      pass(p_label);
    else
      fail(p_label || ': expected TRUE');
    end if;
  end assert_true;

  procedure assert_false(
    p_label     in varchar2,
    p_condition in boolean
  ) is
  begin
    if p_condition then
      fail(p_label || ': expected FALSE');
    else
      pass(p_label);
    end if;
  end assert_false;

  procedure assert_number(
    p_label    in varchar2,
    p_actual   in number,
    p_expected in number
  ) is
  begin
    if p_actual = p_expected then
      pass(p_label || ' = ' || p_expected);
    else
      fail(
        p_label || ': expected ' || p_expected ||
        ', found ' || coalesce(to_char(p_actual), 'NULL')
      );
    end if;
  end assert_number;

  procedure assert_text(
    p_label    in varchar2,
    p_actual   in varchar2,
    p_expected in varchar2
  ) is
  begin
    if p_actual = p_expected then
      pass(p_label || ' = ' || p_expected);
    else
      fail(
        p_label || ': expected ' || p_expected ||
        ', found ' || coalesce(p_actual, 'NULL')
      );
    end if;
  end assert_text;
begin
  dbms_output.put_line('P04 TEST SUITE: START');

  ------------------------------------------------------------------------------
  -- 01. Utility behavior and typed settings
  ------------------------------------------------------------------------------

  assert_text(
    'code normalization',
    of_util_api.normalize_code('  service_agent  '),
    'SERVICE_AGENT'
  );

  assert_text(
    'username normalization',
    of_util_api.normalize_username('  Layla.Employee  '),
    'LAYLA.EMPLOYEE'
  );

  assert_number(
    'number setting',
    of_util_api.get_setting_number('SLA_WARNING_PERCENT'),
    80
  );

  assert_text(
    'text setting',
    of_util_api.get_setting_text('DEFAULT_TIMEZONE'),
    'Africa/Cairo'
  );

  l_actual_boolean :=
    of_util_api.get_setting_boolean('ENABLE_EMAIL_NOTIFICATIONS');
  assert_true('boolean setting', l_actual_boolean);

  assert_text(
    'missing text setting returns supplied default',
    of_util_api.get_setting_text('P04_MISSING_SETTING', 'fallback'),
    'fallback'
  );

  if length(of_util_api.new_correlation_id()) = 32 then
    pass('correlation ID has 32 hexadecimal characters');
  else
    fail('correlation ID must have 32 hexadecimal characters');
  end if;

  ------------------------------------------------------------------------------
  -- 02. Build a transaction-local identity for the actual SQL Scripts actor.
  -- No test-only impersonation hook is added to the production package.
  ------------------------------------------------------------------------------

  savepoint p04_test_start;

  l_username := of_security_api.current_username();

  select id into l_department_id
    from of_departments
   where code = 'IT';

  select id into l_location_id
    from of_locations
   where code = 'CAI-HQ';

  begin
    select id
      into l_user_id
      from of_app_users
     where upper(trim(username)) = l_username;

    update of_app_users
       set is_active = 'Y',
           updated_at = systimestamp,
           updated_by = 'P04_TEST'
     where id = l_user_id;
  exception
    when no_data_found then
      insert into of_app_users (
        username,
        email,
        display_name,
        department_id,
        location_id,
        locale_code,
        timezone_name,
        is_active,
        created_by,
        updated_by
      ) values (
        l_username,
        'p04.' || lower(substr(of_util_api.new_correlation_id(), 1, 20)) ||
          '@example.invalid',
        'P04 Transaction Test Actor',
        l_department_id,
        l_location_id,
        'en',
        'Africa/Cairo',
        'Y',
        'P04_TEST',
        'P04_TEST'
      ) returning id into l_user_id;
  end;

  select department_id
    into l_department_id
    from of_app_users
   where id = l_user_id;

  -- Make the role test deterministic even if the workspace identity was mapped
  -- previously. ROLLBACK later restores every original grant state.
  update of_user_roles
     set is_active = 'N',
         revoked_at = systimestamp,
         revoked_by_user_id = null,
         updated_at = systimestamp,
         updated_by = 'P04_TEST'
   where user_id = l_user_id;

  select id into l_employee_role_id
    from of_roles
   where code = 'EMPLOYEE';

  merge into of_user_roles t
  using (
    select l_user_id user_id,
           l_employee_role_id role_id
      from dual
  ) s
  on (t.user_id = s.user_id and t.role_id = s.role_id)
  when matched then update set
    t.is_active = 'Y',
    t.granted_at = systimestamp,
    t.granted_by_user_id = null,
    t.revoked_at = null,
    t.revoked_by_user_id = null,
    t.updated_at = systimestamp,
    t.updated_by = 'P04_TEST'
  when not matched then insert (
    user_id,
    role_id,
    is_active,
    granted_at,
    granted_by_user_id,
    created_by,
    updated_by
  ) values (
    s.user_id,
    s.role_id,
    'Y',
    systimestamp,
    null,
    'P04_TEST',
    'P04_TEST'
  );

  assert_number(
    'server identity maps to test user',
    of_security_api.current_user_id(),
    l_user_id
  );
  assert_true('active mapped identity is authenticated',
              of_security_api.is_authenticated());
  assert_true('granted role is recognized',
              of_security_api.has_role('employee'));
  assert_false('unknown role is not recognized',
               of_security_api.has_role('NOT_A_ROLE'));

  begin
    of_security_api.assert_role('NOT_A_ROLE');
    fail('assert_role accepted a role the current user does not hold');
  exception
    when others then
      if sqlcode = -20990 then
        raise;
      elsif sqlcode = -20022 then
        pass('missing role is rejected by the server');
      else
        fail('unexpected missing-role error: ' || sqlerrm);
      end if;
  end;

  ------------------------------------------------------------------------------
  -- 03. Row-scope security: own ticket allowed, another user ticket hidden.
  ------------------------------------------------------------------------------

  select id, default_priority_id
    into l_category_id, l_priority_id
    from of_service_categories
   where code = 'ACCOUNT_ACCESS';

  l_ticket_no := 'TKT-P04-' || substr(of_util_api.new_correlation_id(), 1, 12);

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
    created_by,
    updated_by
  ) values (
    l_ticket_no,
    l_user_id,
    l_department_id,
    l_category_id,
    l_priority_id,
    l_location_id,
    'DRAFT',
    'WEB',
    'P04 security scope test',
    'This transaction-local ticket proves requester ownership scope.',
    'P04_TEST',
    'P04_TEST'
  ) returning id into l_ticket_id;

  select min(id)
    into l_other_ticket_id
    from of_tickets
   where requester_user_id <> l_user_id
     and ticket_no like 'TKT-DEMO-%';

  assert_true('requester can view own ticket',
              of_security_api.can_view_ticket(l_ticket_id));
  assert_false('employee cannot view another requester ticket',
               of_security_api.can_view_ticket(l_other_ticket_id));

  begin
    of_security_api.assert_can_view_ticket(l_other_ticket_id);
    fail('assert_can_view_ticket exposed an out-of-scope ticket');
  exception
    when others then
      if sqlcode = -20990 then
        raise;
      elsif sqlcode = -20023 then
        pass('out-of-scope ticket is rejected without revealing its details');
      else
        fail('unexpected ticket-scope error: ' || sqlerrm);
      end if;
  end;

  ------------------------------------------------------------------------------
  -- 04. Audit API and trigger: attribution, sanitization, immutability.
  ------------------------------------------------------------------------------

  l_correlation_id := of_audit_api.record_event(
    p_action_code      => 'P04_TEST',
    p_entity_type_code => 'TICKET',
    p_entity_id        => l_ticket_id,
    p_entity_key       => l_ticket_no,
    p_old_values_json  => '{"status":"NONE"}',
    p_new_values_json  =>
      '{"status":"DRAFT","changes":[{"field":"subject"}]}'
  );

  select count(*)
    into l_actual_number
    from of_audit_log
   where correlation_id = l_correlation_id
     and actor_user_id = l_user_id
     and actor_name = l_username
     and action_code = 'P04_TEST'
     and entity_type_code = 'TICKET';
  assert_number('audit API derives the current actor', l_actual_number, 1);

  insert into of_audit_log (
    actor_user_id,
    actor_name,
    action_code,
    entity_type_code,
    entity_id,
    entity_key,
    old_values_json,
    new_values_json,
    correlation_id
  ) values (
    null,
    'FORGED_BROWSER_ACTOR',
    'p04_direct_test',
    'ticket',
    l_ticket_id,
    l_ticket_no,
    '{"status":"NONE"}',
    '{"status":"DRAFT"}',
    null
  ) returning id into l_direct_audit_id;

  select actor_name
    into l_actual_text
    from of_audit_log
   where id = l_direct_audit_id;
  assert_text(
    'audit trigger replaces a forged actor',
    l_actual_text,
    l_username
  );

  begin
    update of_audit_log
       set action_code = 'FORGED_UPDATE'
     where correlation_id = l_correlation_id;

    fail('audit row accepted UPDATE');
  exception
    when others then
      if sqlcode = -20990 then
        raise;
      elsif sqlcode = -20015 then
        pass('audit UPDATE is rejected');
      else
        fail('unexpected audit immutability error: ' || sqlerrm);
      end if;
  end;

  begin
    l_actual_text := of_audit_api.record_event(
      p_action_code      => 'P04_TEST',
      p_entity_type_code => 'TICKET',
      p_entity_id        => l_ticket_id,
      p_new_values_json  =>
        '{"profile":{"client_secret":"must-never-be-logged"}}'
    );

    fail('audit API accepted a nested sensitive key');
  exception
    when others then
      if sqlcode = -20990 then
        raise;
      elsif sqlcode = -20014 then
        pass('nested sensitive audit key is rejected');
      else
        fail('unexpected sensitive-payload error: ' || sqlerrm);
      end if;
  end;

  begin
    l_actual_text := of_audit_api.record_event(
      p_action_code      => 'P04_TEST',
      p_entity_type_code => 'TICKET',
      p_entity_id        => l_ticket_id,
      p_new_values_json  => '{not-valid-json}'
    );

    fail('audit API accepted invalid JSON');
  exception
    when others then
      if sqlcode = -20990 then
        raise;
      elsif sqlcode = -20014 then
        pass('invalid audit JSON is rejected');
      else
        fail('unexpected invalid-JSON error: ' || sqlerrm);
      end if;
  end;

  -- Proves that OF_AUDIT_API does not commit the caller's business transaction.
  rollback to p04_test_start;

  select count(*)
    into l_actual_number
    from of_audit_log
   where correlation_id = l_correlation_id;
  assert_number('audit row rolls back with caller transaction', l_actual_number, 0);

  rollback;

  ------------------------------------------------------------------------------
  -- 05. Error API: diagnostics survive rollback, user message stays safe.
  ------------------------------------------------------------------------------

  begin
    raise_application_error(-20888, 'P04 synthetic failure for logger test');
  exception
    when others then
      l_error_correlation := of_error_api.log_current_error(
        p_location_code => 'P04.TEST.ERROR_HANDLER',
        p_is_handled    => 'Y'
      );
  end;

  select count(*)
    into l_actual_number
    from of_error_log
   where correlation_id = l_error_correlation
     and location_code = 'P04.TEST.ERROR_HANDLER'
     and is_handled = 'Y'
     and error_message like '%ORA-20888%';
  assert_number('autonomous error row is committed', l_actual_number, 1);

  l_actual_text := of_error_api.user_message(l_error_correlation);

  if instr(l_actual_text, l_error_correlation) > 0
     and instr(upper(l_actual_text), 'ORA-') = 0 then
    pass('user message contains only a safe reference');
  else
    fail('user message leaked technical details or omitted its reference');
  end if;

  delete from of_error_log
   where correlation_id = l_error_correlation;
  commit;
  l_error_correlation := null;

  dbms_output.put_line('P04 TEST SUITE: PASS');
exception
  when others then
    rollback;

    if l_error_correlation is not null then
      delete from of_error_log
       where correlation_id = l_error_correlation;
      commit;
    end if;

    dbms_output.put_line('P04 TEST SUITE: FAIL - ' || sqlerrm);
    raise;
end;
/

--------------------------------------------------------------------------------
-- End P04 test suite. Expected SQL Scripts statements: 1.
--------------------------------------------------------------------------------
