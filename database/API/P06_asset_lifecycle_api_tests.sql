--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P06 - Asset Lifecycle API Tests
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Safety: All user/role/asset/history/audit test DML is transaction-local and
--         rolled back. The production package contains no test impersonation.
-- Expected final DBMS_OUTPUT: P06 TEST SUITE: PASS
--------------------------------------------------------------------------------

declare
  l_username          varchar2(255 char);
  l_actor_user_id     number;
  l_department_id     number;
  l_employee_role_id  number;
  l_admin_role_id     number;
  l_layla_id          number;
  l_youssef_id        number;
  l_cairo_id          number;
  l_alex_id           number;
  l_laptop_type_id    number;
  l_furniture_type_id number;
  l_suffix            varchar2(12 char);

  l_asset_id          number;
  l_lost_asset_id     number;
  l_retired_asset_id  number;
  l_version           number;
  l_lost_version      number;
  l_retired_version   number;
  l_reservation_id    number;
  l_assignment_id     number;
  l_repair_id         number;
  l_actual_number     number;
  l_actual_text       varchar2(4000 char);

  procedure pass(p_label in varchar2) is
  begin
    dbms_output.put_line('PASS - ' || p_label);
  end pass;

  procedure fail(p_label in varchar2) is
  begin
    raise_application_error(-20990, p_label);
  end fail;

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
  dbms_output.put_line('P06 TEST SUITE: START');
  savepoint p06_test_start;

  ------------------------------------------------------------------------------
  -- 01. Map the real SQL Scripts identity and begin with EMPLOYEE only.
  ------------------------------------------------------------------------------

  l_username := of_security_api.current_username();
  l_suffix := substr(of_util_api.new_correlation_id(), 1, 12);

  select id into l_department_id
    from of_departments
   where code = 'IT';

  select id into l_cairo_id
    from of_locations
   where code = 'CAI-HQ';

  select id into l_alex_id
    from of_locations
   where code = 'ALX-OFFICE';

  begin
    select id into l_actor_user_id
      from of_app_users
     where upper(trim(username)) = l_username;

    update of_app_users
       set is_active = 'Y',
           updated_at = systimestamp,
           updated_by = 'P06_TEST'
     where id = l_actor_user_id;
  exception
    when no_data_found then
      insert into of_app_users (
        username, email, display_name, department_id, location_id,
        locale_code, timezone_name, is_active, created_by, updated_by
      ) values (
        l_username,
        'p06.' || lower(l_suffix) || '@example.invalid',
        'P06 Transaction Test Actor', l_department_id, l_cairo_id,
        'en', 'Africa/Cairo', 'Y', 'P06_TEST', 'P06_TEST'
      ) returning id into l_actor_user_id;
  end;

  update of_user_roles
     set is_active = 'N',
         revoked_at = systimestamp,
         revoked_by_user_id = null,
         updated_at = systimestamp,
         updated_by = 'P06_TEST'
   where user_id = l_actor_user_id;

  select id into l_employee_role_id
    from of_roles
   where code = 'EMPLOYEE';

  select id into l_admin_role_id
    from of_roles
   where code = 'OPERATIONS_ADMIN';

  merge into of_user_roles t
  using (
    select l_actor_user_id user_id, l_employee_role_id role_id from dual
  ) s
  on (t.user_id = s.user_id and t.role_id = s.role_id)
  when matched then update set
    t.is_active = 'Y', t.granted_at = systimestamp,
    t.granted_by_user_id = null, t.revoked_at = null,
    t.revoked_by_user_id = null, t.updated_at = systimestamp,
    t.updated_by = 'P06_TEST'
  when not matched then insert (
    user_id, role_id, is_active, granted_at, granted_by_user_id,
    created_by, updated_by
  ) values (
    s.user_id, s.role_id, 'Y', systimestamp, null,
    'P06_TEST', 'P06_TEST'
  );

  select id into l_layla_id
    from of_app_users
   where upper(username) = 'LAYLA.EMPLOYEE' and is_active = 'Y';

  select id into l_youssef_id
    from of_app_users
   where upper(username) = 'YOUSSEF.EMPLOYEE' and is_active = 'Y';

  select id into l_laptop_type_id
    from of_asset_types
   where code = 'LAPTOP' and is_active = 'Y';

  select id into l_furniture_type_id
    from of_asset_types
   where code = 'FURNITURE' and is_active = 'Y';

  begin
    of_asset_api.register_asset(
      p_asset_tag         => 'AST-P06T-AUTH-' || l_suffix,
      p_asset_type_id     => l_laptop_type_id,
      p_serial_number     => 'P06-AUTH-' || l_suffix,
      p_asset_name        => 'Unauthorized test asset',
      p_location_id       => l_cairo_id,
      p_asset_id          => l_asset_id,
      p_row_version       => l_version
    );
    fail('employee-only actor registered an asset');
  exception
    when others then
      if sqlcode = -20990 then raise;
      elsif sqlcode = -20205 then
        pass('employee-only actor cannot register assets');
      else
        fail('unexpected authorization error: ' || sqlerrm);
      end if;
  end;

  ------------------------------------------------------------------------------
  -- 02. Add OPERATIONS_ADMIN and prove type-level serial policy.
  ------------------------------------------------------------------------------

  merge into of_user_roles t
  using (
    select l_actor_user_id user_id, l_admin_role_id role_id from dual
  ) s
  on (t.user_id = s.user_id and t.role_id = s.role_id)
  when matched then update set
    t.is_active = 'Y', t.granted_at = systimestamp,
    t.granted_by_user_id = null, t.revoked_at = null,
    t.revoked_by_user_id = null, t.updated_at = systimestamp,
    t.updated_by = 'P06_TEST'
  when not matched then insert (
    user_id, role_id, is_active, granted_at, granted_by_user_id,
    created_by, updated_by
  ) values (
    s.user_id, s.role_id, 'Y', systimestamp, null,
    'P06_TEST', 'P06_TEST'
  );

  begin
    of_asset_api.register_asset(
      p_asset_tag       => 'AST-P06T-NOSERIAL-' || l_suffix,
      p_asset_type_id   => l_laptop_type_id,
      p_asset_name      => 'Missing serial test',
      p_location_id     => l_cairo_id,
      p_asset_id        => l_asset_id,
      p_row_version     => l_version
    );
    fail('serial-required type accepted a null serial number');
  exception
    when others then
      if sqlcode = -20990 then raise;
      elsif sqlcode = -20207 then
        pass('serial-required type rejects a null serial number');
      else
        fail('unexpected serial-policy error: ' || sqlerrm);
      end if;
  end;

  ------------------------------------------------------------------------------
  -- 03. Main lifecycle: register, reserve, assign, transfer, and return.
  ------------------------------------------------------------------------------

  of_asset_api.register_asset(
    p_asset_tag         => 'AST-P06T-MAIN-' || l_suffix,
    p_asset_type_id     => l_laptop_type_id,
    p_serial_number     => 'P06-MAIN-' || l_suffix,
    p_asset_name        => 'P06 main lifecycle laptop',
    p_description       => 'Transaction-local test asset',
    p_location_id       => l_cairo_id,
    p_acquisition_date  => trunc(current_date),
    p_purchase_cost     => 25000,
    p_currency_code     => 'egp',
    p_asset_id          => l_asset_id,
    p_row_version       => l_version
  );
  assert_number('registered row version', l_version, 1);

  select status_code into l_actual_text
    from of_assets where id = l_asset_id;
  assert_text('registered state', l_actual_text, 'IN_STOCK');

  begin
    of_asset_api.reserve_asset(
      p_asset_id             => l_asset_id,
      p_expected_row_version => 99,
      p_reserved_for_user_id => l_layla_id,
      p_reservation_id       => l_reservation_id,
      p_new_row_version      => l_actual_number
    );
    fail('stale asset row version was accepted');
  exception
    when others then
      if sqlcode = -20990 then raise;
      elsif sqlcode = -20202 then
        pass('stale asset row version is rejected');
      else
        fail('unexpected stale-version error: ' || sqlerrm);
      end if;
  end;

  of_asset_api.reserve_asset(
    p_asset_id             => l_asset_id,
    p_expected_row_version => l_version,
    p_reserved_for_user_id => l_layla_id,
    p_expires_at           => systimestamp + interval '2' day,
    p_reason_text          => 'Laptop onboarding reservation',
    p_reservation_id       => l_reservation_id,
    p_new_row_version      => l_version
  );
  assert_number('reserve increments version', l_version, 2);

  begin
    insert into of_asset_reservations (
      asset_id, reserved_for_user_id, reserved_by_user_id,
      status_code, created_by, updated_by
    ) values (
      l_asset_id, l_youssef_id, l_actor_user_id,
      'ACTIVE', 'P06_TEST', 'P06_TEST'
    );
    fail('duplicate active reservation bypassed unique index');
  exception
    when dup_val_on_index then
      pass('unique index rejects a second active reservation');
  end;

  of_asset_api.assign_asset(
    p_asset_id             => l_asset_id,
    p_expected_row_version => l_version,
    p_assigned_to_user_id  => l_layla_id,
    p_condition_out_code   => 'new',
    p_to_location_id       => l_cairo_id,
    p_notes                => 'Issued after reservation',
    p_assignment_id        => l_assignment_id,
    p_new_row_version      => l_version
  );
  assert_number('assign increments version', l_version, 3);

  select status_code into l_actual_text
    from of_asset_reservations where id = l_reservation_id;
  assert_text('matching reservation fulfilled', l_actual_text, 'FULFILLED');

  begin
    insert into of_asset_assignments (
      asset_id, assigned_to_user_id, assigned_by_user_id,
      condition_out_code, created_by, updated_by
    ) values (
      l_asset_id, l_youssef_id, l_actor_user_id,
      'GOOD', 'P06_TEST', 'P06_TEST'
    );
    fail('duplicate active assignment bypassed unique index');
  exception
    when dup_val_on_index then
      pass('unique index rejects a second active assignment');
  end;

  of_asset_api.transfer_asset(
    p_asset_id                => l_asset_id,
    p_expected_row_version    => l_version,
    p_new_custodian_user_id   => l_youssef_id,
    p_condition_in_code       => 'good',
    p_condition_out_code      => 'good',
    p_to_location_id          => l_alex_id,
    p_reason_text             => 'Temporary cross-office transfer',
    p_new_assignment_id       => l_assignment_id,
    p_new_row_version         => l_version
  );
  assert_number('transfer increments version', l_version, 4);

  select count(*) into l_actual_number
    from of_asset_assignments
   where asset_id = l_asset_id and returned_at is null
     and assigned_to_user_id = l_youssef_id;
  assert_number('transfer leaves one new custodian', l_actual_number, 1);

  of_asset_api.return_asset(
    p_asset_id             => l_asset_id,
    p_expected_row_version => l_version,
    p_return_location_id   => l_cairo_id,
    p_condition_in_code    => 'fair',
    p_notes                => 'Returned to central stock',
    p_new_row_version      => l_version
  );
  assert_number('return increments version', l_version, 5);

  ------------------------------------------------------------------------------
  -- 04. Repair to custodian, repair from custody, then repair to stock.
  ------------------------------------------------------------------------------

  of_asset_api.open_repair(
    p_asset_id             => l_asset_id,
    p_expected_row_version => l_version,
    p_problem_description  => 'Battery fails under normal load.',
    p_provider_name        => 'Synthetic Repair Lab',
    p_repair_location_id   => l_cairo_id,
    p_repair_id            => l_repair_id,
    p_new_row_version      => l_version
  );
  assert_number('open repair increments version', l_version, 6);

  begin
    insert into of_asset_repairs (
      asset_id, status_code, problem_description, created_by, updated_by
    ) values (
      l_asset_id, 'OPEN', 'Second active repair must fail.',
      'P06_TEST', 'P06_TEST'
    );
    fail('duplicate active repair bypassed unique index');
  exception
    when dup_val_on_index then
      pass('unique index rejects a second active repair');
  end;

  of_asset_api.complete_repair_to_custodian(
    p_asset_id               => l_asset_id,
    p_expected_row_version   => l_version,
    p_repair_id              => l_repair_id,
    p_resolution_description => 'Battery replaced and diagnostics passed.',
    p_custodian_user_id      => l_layla_id,
    p_condition_out_code     => 'good',
    p_to_location_id         => l_cairo_id,
    p_assignment_id          => l_assignment_id,
    p_new_row_version        => l_version
  );
  assert_number('repair-to-custodian increments version', l_version, 7);

  of_asset_api.open_repair(
    p_asset_id             => l_asset_id,
    p_expected_row_version => l_version,
    p_problem_description  => 'Keyboard intermittently disconnects.',
    p_provider_name        => 'Synthetic Repair Lab',
    p_repair_location_id   => l_alex_id,
    p_condition_in_code    => 'damaged',
    p_repair_id            => l_repair_id,
    p_new_row_version      => l_version
  );
  assert_number('repair from custody increments version', l_version, 8);

  select count(*) into l_actual_number
    from of_asset_assignments
   where asset_id = l_asset_id and returned_at is null;
  assert_number('repair closes active custody', l_actual_number, 0);

  of_asset_api.complete_repair_to_stock(
    p_asset_id               => l_asset_id,
    p_expected_row_version   => l_version,
    p_repair_id              => l_repair_id,
    p_resolution_description => 'Keyboard cable reseated and tested.',
    p_stock_location_id      => l_cairo_id,
    p_cost_amount            => 125,
    p_currency_code          => 'EGP',
    p_new_row_version        => l_version
  );
  assert_number('repair-to-stock increments version', l_version, 9);

  of_asset_api.reserve_asset(
    p_asset_id             => l_asset_id,
    p_expected_row_version => l_version,
    p_reserved_for_user_id => l_youssef_id,
    p_reason_text          => 'Short hold before deployment',
    p_reservation_id       => l_reservation_id,
    p_new_row_version      => l_version
  );
  assert_number('second reserve increments version', l_version, 10);

  of_asset_api.release_reservation(
    p_asset_id             => l_asset_id,
    p_expected_row_version => l_version,
    p_reason_text          => 'Deployment plan changed',
    p_new_row_version      => l_version
  );
  assert_number('release increments version', l_version, 11);

  select count(*) into l_actual_number
    from of_asset_status_history
   where asset_id = l_asset_id;
  assert_number('main asset history event count', l_actual_number, 11);

  select count(*) into l_actual_number
    from of_audit_log
   where entity_type_code = 'ASSET'
     and entity_id = l_asset_id;
  assert_number('main asset audit event count', l_actual_number, 11);

  begin
    update of_asset_status_history
       set reason_text = 'Tamper attempt'
     where id = (
       select min(id) from of_asset_status_history where asset_id = l_asset_id
     );
    fail('asset history update was allowed');
  exception
    when others then
      if sqlcode = -20990 then raise;
      elsif sqlcode = -20220 then
        pass('asset history update is rejected');
      else
        fail('unexpected history-guard error: ' || sqlerrm);
      end if;
  end;

  ------------------------------------------------------------------------------
  -- 05. Lost is terminal and closes active custody.
  ------------------------------------------------------------------------------

  of_asset_api.register_asset(
    p_asset_tag       => 'AST-P06T-LOST-' || l_suffix,
    p_asset_type_id   => l_laptop_type_id,
    p_serial_number   => 'P06-LOST-' || l_suffix,
    p_asset_name      => 'P06 lost lifecycle laptop',
    p_location_id     => l_cairo_id,
    p_asset_id        => l_lost_asset_id,
    p_row_version     => l_lost_version
  );

  of_asset_api.assign_asset(
    p_asset_id             => l_lost_asset_id,
    p_expected_row_version => l_lost_version,
    p_assigned_to_user_id  => l_layla_id,
    p_condition_out_code   => 'good',
    p_assignment_id        => l_assignment_id,
    p_new_row_version      => l_lost_version
  );

  of_asset_api.mark_lost(
    p_asset_id             => l_lost_asset_id,
    p_expected_row_version => l_lost_version,
    p_reason_text          => 'Not recovered after documented search',
    p_new_row_version      => l_lost_version
  );
  assert_number('lost lifecycle version', l_lost_version, 3);

  select status_code into l_actual_text
    from of_assets where id = l_lost_asset_id;
  assert_text('lost terminal state', l_actual_text, 'LOST');

  select count(*) into l_actual_number
    from of_asset_assignments
   where asset_id = l_lost_asset_id
     and returned_at is null;
  assert_number('lost closes active custody', l_actual_number, 0);

  begin
    of_asset_api.assign_asset(
      p_asset_id             => l_lost_asset_id,
      p_expected_row_version => l_lost_version,
      p_assigned_to_user_id  => l_youssef_id,
      p_condition_out_code   => 'good',
      p_assignment_id        => l_assignment_id,
      p_new_row_version      => l_actual_number
    );
    fail('terminal LOST asset was reassigned');
  exception
    when others then
      if sqlcode = -20990 then raise;
      elsif sqlcode = -20204 then
        pass('terminal LOST asset rejects reassignment');
      else
        fail('unexpected terminal-state error: ' || sqlerrm);
      end if;
  end;

  ------------------------------------------------------------------------------
  -- 06. Retiring from repair cancels the open repair. Furniture needs no serial.
  ------------------------------------------------------------------------------

  of_asset_api.register_asset(
    p_asset_tag       => 'AST-P06T-RET-' || l_suffix,
    p_asset_type_id   => l_furniture_type_id,
    p_asset_name      => 'P06 retirement test chair',
    p_location_id     => l_alex_id,
    p_asset_id        => l_retired_asset_id,
    p_row_version     => l_retired_version
  );

  of_asset_api.open_repair(
    p_asset_id             => l_retired_asset_id,
    p_expected_row_version => l_retired_version,
    p_problem_description  => 'Frame is no longer safe for service.',
    p_repair_id            => l_repair_id,
    p_new_row_version      => l_retired_version
  );

  of_asset_api.retire_asset(
    p_asset_id             => l_retired_asset_id,
    p_expected_row_version => l_retired_version,
    p_reason_text          => 'Repair is uneconomical and item is unsafe',
    p_new_row_version      => l_retired_version
  );
  assert_number('retirement lifecycle version', l_retired_version, 3);

  select status_code into l_actual_text
    from of_asset_repairs where id = l_repair_id;
  assert_text('retirement cancels active repair', l_actual_text, 'CANCELLED');

  select count(*) into l_actual_number
    from of_asset_status_history h
    join of_assets a on a.id = h.asset_id
   where a.asset_tag like 'AST-P06T-%';
  assert_number('all test asset history event count', l_actual_number, 17);

  select count(*) into l_actual_number
    from of_audit_log
   where entity_type_code = 'ASSET'
     and entity_key like 'AST-P06T-%';
  assert_number('all test asset audit event count', l_actual_number, 17);

  ------------------------------------------------------------------------------
  -- 07. Roll back the full test transaction and prove zero residue.
  ------------------------------------------------------------------------------

  rollback to p06_test_start;

  select count(*) into l_actual_number
    from of_assets
   where asset_tag like 'AST-P06T-%';
  assert_number('asset residue after rollback', l_actual_number, 0);

  select count(*) into l_actual_number
    from of_audit_log
   where entity_type_code = 'ASSET'
     and entity_key like 'AST-P06T-%';
  assert_number('audit residue after rollback', l_actual_number, 0);

  dbms_output.put_line('P06 TEST SUITE: PASS');
exception
  when others then
    rollback to p06_test_start;
    raise;
end;
/

--------------------------------------------------------------------------------
-- End P06 test suite. Expected SQL Scripts statements: 1.
--------------------------------------------------------------------------------
