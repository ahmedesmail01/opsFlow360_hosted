--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P07 - Procurement, Receiving, and Inventory API Tests
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Safety: Every test mutation is made after one savepoint and rolled back.
-- Expected final DBMS_OUTPUT: P07 TEST SUITE: PASS
--------------------------------------------------------------------------------

declare
  l_username            varchar2(255 char);
  l_suffix              varchar2(12 char);
  l_actor_user_id       number;
  l_requester_user_id   number;
  l_department_id       number;
  l_location_id         number;
  l_catalog_item_id     number;
  l_supplier_id         number;

  l_request_id          number;
  l_request_item_id     number;
  l_request_no          varchar2(30 char);
  l_request_status      varchar2(30 char);
  l_request_version     number;

  l_po1_id              number;
  l_po2_id              number;
  l_po1_item_id         number;
  l_po2_item_id         number;
  l_po_no               varchar2(30 char);
  l_po_status           varchar2(30 char);
  l_po1_version         number;
  l_po2_version         number;

  l_receipt1_id         number;
  l_receipt2_id         number;
  l_receipt3_id         number;
  l_receipt4_id         number;
  l_replay_receipt_id   number;
  l_receipt_item_id     number;
  l_receipt_no          varchar2(30 char);
  l_replay_receipt_no   varchar2(30 char);
  l_receipt1_version    number;
  l_receipt2_version    number;
  l_receipt3_version    number;
  l_receipt4_version    number;
  l_replay_version      number;
  l_received_at4        timestamp with local time zone;

  l_actual_number       number;
  l_baseline_balance    number;
  l_baseline_ledger     number;
  l_before_count        number;
  l_after_count         number;
  l_actual_text         varchar2(4000 char);

  procedure pass(p_label in varchar2) is
  begin
    dbms_output.put_line('PASS - ' || p_label);
  end pass;
;

procedure fail (p_label in varchar2) is
begin raise_application_error (-20990, p_label);

end fail;

procedure assert_number (
    p_label in varchar2,
    p_actual in number,
    p_expected in number
) is
begin if p_actual = p_expected then pass (
    p_label || ' = ' || p_expected
);

else fail (
    p_label || ': expected ' || p_expected || ', found ' || coalesce(to_char(p_actual), 'NULL')
);

end if;

end assert_number;

procedure assert_text (
    p_label in varchar2,
    p_actual in varchar2,
    p_expected in varchar2
) is
begin if p_actual = p_expected then pass (
    p_label || ' = ' || p_expected
);

else fail (
    p_label || ': expected ' || p_expected || ', found ' || coalesce(p_actual, 'NULL')
);

end if;

end assert_text;

begin
  dbms_output.put_line('P07 TEST SUITE: START');
  savepoint p07_test_start;

  ------------------------------------------------------------------------------
  -- 01. Map the real SQL Scripts identity; begin with EMPLOYEE only.
  ------------------------------------------------------------------------------

  l_username := of_security_api.current_username();
  l_suffix := substr(of_util_api.new_correlation_id(), 1, 12);

  select id into l_department_id
    from of_departments
   where code = 'HR';

  select id into l_location_id
    from of_locations
   where code = 'CAI-HQ' and is_active = 'Y';

  select id into l_requester_user_id
    from of_app_users
   where upper(username) = 'LAYLA.EMPLOYEE' and is_active = 'Y';

  select id into l_catalog_item_id
    from of_catalog_items
   where code = 'OFFICE_PAPER_A4' and is_active = 'Y';

  select id into l_supplier_id
    from of_suppliers
   where supplier_code = 'NILE_TECH' and is_active = 'Y';

  select coalesce(max(quantity_on_hand), 0)
    into l_baseline_balance
    from of_inventory_balances
   where catalog_item_id = l_catalog_item_id
     and location_id = l_location_id;

  select coalesce(sum(quantity_delta), 0)
    into l_baseline_ledger
    from of_stock_movements
   where catalog_item_id = l_catalog_item_id
     and location_id = l_location_id;

  assert_number(
    'starting balance agrees with ledger',
    l_baseline_balance, l_baseline_ledger
  );

  begin
    select id into l_actor_user_id
      from of_app_users
     where upper(trim(username)) = l_username;

    update of_app_users
       set department_id = l_department_id,
           location_id = l_location_id,
           is_active = 'Y',
           updated_at = systimestamp,
           updated_by = 'P07_TEST'
     where id = l_actor_user_id;
  exception
    when no_data_found then
      insert into of_app_users (
        username, email, display_name, department_id, location_id,
        locale_code, timezone_name, is_active, created_by, updated_by
      ) values (
        l_username,
        'p07.' || lower(l_suffix) || '@example.invalid',
        'P07 Transaction Test Actor', l_department_id, l_location_id,
        'en', 'Africa/Cairo', 'Y', 'P07_TEST', 'P07_TEST'
      ) returning id into l_actor_user_id;
  end;

  if l_actor_user_id = l_requester_user_id then
    fail('Run the test as a workspace user other than LAYLA.EMPLOYEE.');
  end if;

  update of_user_roles
     set is_active = 'N',
         revoked_at = systimestamp,
         revoked_by_user_id = null,
         updated_at = systimestamp,
         updated_by = 'P07_TEST'
   where user_id = l_actor_user_id;

  merge into of_user_roles t
  using (
    select l_actor_user_id user_id, r.id role_id
      from of_roles r
     where r.code = 'EMPLOYEE'
  ) s
  on (t.user_id = s.user_id and t.role_id = s.role_id)
  when matched then update set
    t.is_active = 'Y', t.granted_at = systimestamp,
    t.granted_by_user_id = null, t.revoked_at = null,
    t.revoked_by_user_id = null, t.updated_at = systimestamp,
    t.updated_by = 'P07_TEST'
  when not matched then insert (
    user_id, role_id, is_active, granted_at, granted_by_user_id,
    created_by, updated_by
  ) values (
    s.user_id, s.role_id, 'Y', systimestamp, null,
    'P07_TEST', 'P07_TEST'
  );

  begin
    of_procurement_api.create_request_draft(
      p_business_justification => to_clob('Unauthorized on-behalf test'),
      p_requester_user_id      => l_requester_user_id,
      p_request_id             => l_request_id,
      p_request_no             => l_request_no,
      p_row_version            => l_request_version
    );
    fail('employee-only actor created a request for another user');
  exception
    when others then
      if sqlcode = -20990 then raise;
      elsif sqlcode = -20305 then
        pass('employee-only actor cannot create on behalf of another user');
      else
        fail('unexpected on-behalf authorization error: ' || sqlerrm);
      end if;
  end;

  ------------------------------------------------------------------------------
  -- 02. Grant the transaction-test actor all P07 operational roles.
  ------------------------------------------------------------------------------

  for r in (
    select id
      from of_roles
     where code in ('MANAGER', 'OPERATIONS_ADMIN', 'PROCUREMENT_OFFICER')
  ) loop
    merge into of_user_roles t
    using (
      select l_actor_user_id user_id, r.id role_id from dual
    ) s
    on (t.user_id = s.user_id and t.role_id = s.role_id)
    when matched then update set
      t.is_active = 'Y', t.granted_at = systimestamp,
      t.granted_by_user_id = null, t.revoked_at = null,
      t.revoked_by_user_id = null, t.updated_at = systimestamp,
      t.updated_by = 'P07_TEST'
    when not matched then insert (
      user_id, role_id, is_active, granted_at, granted_by_user_id,
      created_by, updated_by
    ) values (
      s.user_id, s.role_id, 'Y', systimestamp, null,
      'P07_TEST', 'P07_TEST'
    );
  end loop;

  -- SETTING_VALUE is a CLOB. Keep every assignment explicitly CLOB-typed;
  -- mixing character literals with a CLOB ELSE branch in one CASE expression
  -- raises ORA-00932 in hosted APEX SQL Scripts.
  update of_app_settings
     set setting_value = to_clob('P07T'),
         updated_at = systimestamp,
         updated_by = 'P07_TEST'
   where setting_code = 'PURCHASE_REQUEST_PREFIX';

  update of_app_settings
     set setting_value = to_clob('P07PO'),
         updated_at = systimestamp,
         updated_by = 'P07_TEST'
   where setting_code = 'PURCHASE_ORDER_PREFIX';

  update of_app_settings
     set setting_value = to_clob('P07GR'),
         updated_at = systimestamp,
         updated_by = 'P07_TEST'
   where setting_code = 'GOODS_RECEIPT_PREFIX';

  update of_app_settings
     set setting_value = to_clob('500'),
         updated_at = systimestamp,
         updated_by = 'P07_TEST'
   where setting_code = 'PROCUREMENT_APPROVAL_THRESHOLD';

  ------------------------------------------------------------------------------
  -- 03. Server-derived request total and the three-stage approval route.
  ------------------------------------------------------------------------------

  of_procurement_api.create_request_draft(
    p_business_justification => to_clob(
      'P07 test: replenish ten A4 paper reams for the HR department.'
    ),
    p_currency_code          => 'EGP',
    p_requester_user_id      => l_requester_user_id,
    p_request_id             => l_request_id,
    p_request_no             => l_request_no,
    p_row_version            => l_request_version
  );
  assert_text('request prefix', substr(l_request_no, 1, 5), 'P07T-');

  of_procurement_api.add_request_item(
    p_request_id           => l_request_id,
    p_expected_row_version => l_request_version,
    p_catalog_item_id      => l_catalog_item_id,
    p_item_description     => 'A4 Office Paper test replenishment',
    p_quantity             => 10,
    p_estimated_unit_price => 100,
    p_required_by_date     => trunc(sysdate) + 7,
    p_request_item_id      => l_request_item_id,
    p_new_row_version      => l_request_version
  );

  update of_purchase_requests
     set total_amount = 1
   where id = l_request_id;

  of_procurement_api.submit_request(
    p_request_id           => l_request_id,
    p_expected_row_version => l_request_version,
    p_admin_reason         => 'Transaction test submits for fictional requester.',
    p_new_row_version      => l_request_version
  );

  select total_amount, status_code
    into l_actual_number, l_actual_text
    from of_purchase_requests
   where id = l_request_id;
  assert_number('server-recalculated request total', l_actual_number, 1000);
  assert_text('high-value route starts', l_actual_text, 'MANAGER_REVIEW');

  of_procurement_api.approve_manager(
    p_request_id           => l_request_id,
    p_expected_row_version => l_request_version,
    p_decision_comment     => 'P07 manager approval test.',
    p_new_row_version      => l_request_version
  );
  select status_code into l_request_status
    from of_purchase_requests where id = l_request_id;
  assert_text('manager route', l_request_status, 'OPERATIONS_REVIEW');

  of_procurement_api.approve_operations(
    p_request_id           => l_request_id,
    p_expected_row_version => l_request_version,
    p_decision_comment     => 'P07 operations approval test.',
    p_new_row_version      => l_request_version
  );
  select status_code into l_request_status
    from of_purchase_requests where id = l_request_id;
  assert_text('operations route', l_request_status, 'PROCUREMENT_REVIEW');

  of_procurement_api.approve_procurement(
    p_request_id           => l_request_id,
    p_expected_row_version => l_request_version,
    p_decision_comment     => 'P07 procurement approval test.',
    p_new_row_version      => l_request_version
  );
  select status_code into l_request_status
    from of_purchase_requests where id = l_request_id;
  assert_text('request approved', l_request_status, 'APPROVED');

  begin
    of_procurement_api.create_order_draft(
      p_request_id         => l_request_id,
      p_expected_row_version => l_request_version - 1,
      p_supplier_id        => l_supplier_id,
      p_po_id              => l_po1_id,
      p_po_no              => l_po_no,
      p_po_row_version     => l_po1_version,
      p_request_row_version => l_actual_number
    );
    fail('stale request version created an order');
  exception
    when others then
      if sqlcode = -20990 then raise;
      elsif sqlcode = -20302 then pass('stale request version is rejected');
      else fail('unexpected stale-version error: ' || sqlerrm);
      end if;
  end;

  ------------------------------------------------------------------------------
  -- 04. Split ordering, over-order protection, and request reconciliation.
  ------------------------------------------------------------------------------

  of_procurement_api.create_order_draft(
    p_request_id          => l_request_id,
    p_expected_row_version => l_request_version,
    p_supplier_id         => l_supplier_id,
    p_po_id               => l_po1_id,
    p_po_no               => l_po_no,
    p_po_row_version      => l_po1_version,
    p_request_row_version => l_request_version
  );
  assert_text('order prefix', substr(l_po_no, 1, 6), 'P07PO-');

  of_procurement_api.add_order_item(
    p_po_id               => l_po1_id,
    p_expected_po_version => l_po1_version,
    p_request_item_id     => l_request_item_id,
    p_ordered_quantity    => 6,
    p_unit_price          => 95,
    p_po_item_id          => l_po1_item_id,
    p_new_po_version      => l_po1_version
  );

  of_procurement_api.issue_order(
    p_po_id                => l_po1_id,
    p_expected_po_version  => l_po1_version,
    p_order_date           => trunc(sysdate),
    p_expected_date        => trunc(sysdate) + 5,
    p_new_po_version       => l_po1_version,
    p_request_status       => l_request_status,
    p_request_row_version  => l_request_version
  );
  assert_text('first order leaves partial request', l_request_status,
              'PARTIALLY_ORDERED');

  of_procurement_api.create_order_draft(
    p_request_id           => l_request_id,
    p_expected_row_version => l_request_version,
    p_supplier_id          => l_supplier_id,
    p_po_id                => l_po2_id,
    p_po_no                => l_po_no,
    p_po_row_version       => l_po2_version,
    p_request_row_version  => l_request_version
  );

  begin
    of_procurement_api.add_order_item(
      p_po_id               => l_po2_id,
      p_expected_po_version => l_po2_version,
      p_request_item_id     => l_request_item_id,
      p_ordered_quantity    => 5,
      p_unit_price          => 96,
      p_po_item_id          => l_po2_item_id,
      p_new_po_version      => l_actual_number
    );
    fail('over-order quantity was accepted');
  exception
    when others then
      if sqlcode = -20990 then raise;
      elsif sqlcode = -20309 then pass('over-order quantity is rejected');
      else fail('unexpected over-order error: ' || sqlerrm);
      end if;
  end;

  of_procurement_api.add_order_item(
    p_po_id               => l_po2_id,
    p_expected_po_version => l_po2_version,
    p_request_item_id     => l_request_item_id,
    p_ordered_quantity    => 4,
    p_unit_price          => 96,
    p_po_item_id          => l_po2_item_id,
    p_new_po_version      => l_po2_version
  );

  of_procurement_api.issue_order(
    p_po_id               => l_po2_id,
    p_expected_po_version => l_po2_version,
    p_order_date          => trunc(sysdate),
    p_expected_date       => trunc(sysdate) + 5,
    p_new_po_version      => l_po2_version,
    p_request_status      => l_request_status,
    p_request_row_version => l_request_version
  );
  assert_text('split orders fully cover request', l_request_status, 'ORDERED');

  ------------------------------------------------------------------------------
  -- 05. Partial receipt, posting replay, and over-receipt protection.
  ------------------------------------------------------------------------------

  of_inventory_api.create_receipt_draft(
    p_po_id               => l_po1_id,
    p_expected_po_version => l_po1_version,
    p_received_at         => systimestamp,
    p_delivery_reference  => 'P07-R1-' || l_suffix,
    p_notes               => 'First partial receipt.',
    p_idempotency_key     => 'P07-R1-' || l_suffix,
    p_receipt_id          => l_receipt1_id,
    p_receipt_no          => l_receipt_no,
    p_receipt_row_version => l_receipt1_version
  );
  assert_text('receipt prefix', substr(l_receipt_no, 1, 6), 'P07GR-');

  of_inventory_api.add_receipt_item(
    p_receipt_id            => l_receipt1_id,
    p_expected_row_version  => l_receipt1_version,
    p_po_item_id            => l_po1_item_id,
    p_quantity_received     => 3,
    p_quantity_accepted     => 3,
    p_quantity_rejected     => 0,
    p_unit_cost             => 95,
    p_location_id           => l_location_id,
    p_receipt_item_id       => l_receipt_item_id,
    p_new_row_version       => l_receipt1_version
  );

  of_inventory_api.post_receipt(
    p_receipt_id            => l_receipt1_id,
    p_expected_row_version  => l_receipt1_version,
    p_idempotency_key       => 'P07-R1-' || l_suffix,
    p_new_row_version       => l_receipt1_version,
    p_po_status             => l_po_status,
    p_po_row_version        => l_po1_version,
    p_request_status        => l_request_status,
    p_request_row_version   => l_request_version
  );
  assert_text('first order is partially received', l_po_status,
              'PARTIALLY_RECEIVED');
  assert_text('request is partially received', l_request_status,
              'PARTIALLY_RECEIVED');

  select count(*) into l_before_count
    from of_stock_movements sm
    join of_goods_receipt_items gri on gri.id = sm.receipt_item_id
   where gri.goods_receipt_id = l_receipt1_id;

  of_inventory_api.post_receipt(
    p_receipt_id            => l_receipt1_id,
    p_expected_row_version  => 1,
    p_idempotency_key       => 'P07-R1-' || l_suffix,
    p_new_row_version       => l_replay_version,
    p_po_status             => l_po_status,
    p_po_row_version        => l_po1_version,
    p_request_status        => l_request_status,
    p_request_row_version   => l_request_version
  );

  select count(*) into l_after_count
    from of_stock_movements sm
    join of_goods_receipt_items gri on gri.id = sm.receipt_item_id
   where gri.goods_receipt_id = l_receipt1_id;
  assert_number('posting replay adds no ledger row', l_after_count,
                l_before_count);

  of_inventory_api.create_receipt_draft(
    p_po_id               => l_po1_id,
    p_expected_po_version => l_po1_version,
    p_received_at         => systimestamp,
    p_delivery_reference  => 'P07-R2-' || l_suffix,
    p_notes               => 'Second partial receipt.',
    p_idempotency_key     => 'P07-R2-' || l_suffix,
    p_receipt_id          => l_receipt2_id,
    p_receipt_no          => l_receipt_no,
    p_receipt_row_version => l_receipt2_version
  );

  begin
    of_inventory_api.add_receipt_item(
      p_receipt_id           => l_receipt2_id,
      p_expected_row_version => l_receipt2_version,
      p_po_item_id           => l_po1_item_id,
      p_quantity_received    => 4,
      p_quantity_accepted    => 4,
      p_quantity_rejected    => 0,
      p_unit_cost            => 95,
      p_location_id          => l_location_id,
      p_receipt_item_id      => l_receipt_item_id,
      p_new_row_version      => l_actual_number
    );
    fail('over-receipt quantity was accepted');
  exception
    when others then
      if sqlcode = -20990 then raise;
      elsif sqlcode = -20309 then pass('over-receipt quantity is rejected');
      else fail('unexpected over-receipt error: ' || sqlerrm);
      end if;
  end;

  of_inventory_api.add_receipt_item(
    p_receipt_id           => l_receipt2_id,
    p_expected_row_version => l_receipt2_version,
    p_po_item_id           => l_po1_item_id,
    p_quantity_received    => 3,
    p_quantity_accepted    => 3,
    p_quantity_rejected    => 0,
    p_unit_cost            => 95,
    p_location_id          => l_location_id,
    p_receipt_item_id      => l_receipt_item_id,
    p_new_row_version      => l_receipt2_version
  );

  of_inventory_api.post_receipt(
    p_receipt_id           => l_receipt2_id,
    p_expected_row_version => l_receipt2_version,
    p_idempotency_key      => 'P07-R2-' || l_suffix,
    p_new_row_version      => l_receipt2_version,
    p_po_status            => l_po_status,
    p_po_row_version       => l_po1_version,
    p_request_status       => l_request_status,
    p_request_row_version  => l_request_version
  );
  assert_text('first order is fully received', l_po_status, 'RECEIVED');

  ------------------------------------------------------------------------------
  -- 06. Complete the second order and close the hierarchy.
  ------------------------------------------------------------------------------

  of_inventory_api.create_receipt_draft(
    p_po_id               => l_po2_id,
    p_expected_po_version => l_po2_version,
    p_received_at         => systimestamp,
    p_delivery_reference  => 'P07-R3-' || l_suffix,
    p_notes               => 'Second order receipt.',
    p_idempotency_key     => 'P07-R3-' || l_suffix,
    p_receipt_id          => l_receipt3_id,
    p_receipt_no          => l_receipt_no,
    p_receipt_row_version => l_receipt3_version
  );

  of_inventory_api.add_receipt_item(
    p_receipt_id           => l_receipt3_id,
    p_expected_row_version => l_receipt3_version,
    p_po_item_id           => l_po2_item_id,
    p_quantity_received    => 4,
    p_quantity_accepted    => 4,
    p_quantity_rejected    => 0,
    p_unit_cost            => 96,
    p_location_id          => l_location_id,
    p_receipt_item_id      => l_receipt_item_id,
    p_new_row_version      => l_receipt3_version
  );

  of_inventory_api.post_receipt(
    p_receipt_id           => l_receipt3_id,
    p_expected_row_version => l_receipt3_version,
    p_idempotency_key      => 'P07-R3-' || l_suffix,
    p_new_row_version      => l_receipt3_version,
    p_po_status            => l_po_status,
    p_po_row_version       => l_po2_version,
    p_request_status       => l_request_status,
    p_request_row_version  => l_request_version
  );
  assert_text('second order is fully received', l_po_status, 'RECEIVED');
  assert_text('request is fully received', l_request_status, 'RECEIVED');

  select quantity_on_hand into l_actual_number
    from of_inventory_balances
   where catalog_item_id = l_catalog_item_id
     and location_id = l_location_id;
  assert_number(
    'balance after all receipts', l_actual_number, l_baseline_balance + 10
  );

  select sum(quantity_delta) into l_actual_number
    from of_stock_movements
   where catalog_item_id = l_catalog_item_id
     and location_id = l_location_id;
  assert_number(
    'ledger after all receipts', l_actual_number, l_baseline_ledger + 10
  );

  begin
    update of_stock_movements
       set reason_text = 'Forbidden direct edit'
     where id = (
       select min(id) from of_stock_movements
        where catalog_item_id = l_catalog_item_id
          and location_id = l_location_id
     );
    fail('stock movement was directly updated');
  exception
    when others then
      if sqlcode = -20990 then raise;
      elsif sqlcode = -20320 then pass('stock ledger blocks direct updates');
      else fail('unexpected ledger-guard error: ' || sqlerrm);
      end if;
  end;

  of_procurement_api.close_order(
    p_po_id               => l_po1_id,
    p_expected_po_version => l_po1_version,
    p_new_po_version      => l_po1_version
  );
  of_procurement_api.close_order(
    p_po_id               => l_po2_id,
    p_expected_po_version => l_po2_version,
    p_new_po_version      => l_po2_version
  );
  of_procurement_api.close_request(
    p_request_id           => l_request_id,
    p_expected_row_version => l_request_version,
    p_new_row_version      => l_request_version
  );
  select status_code into l_request_status
    from of_purchase_requests where id = l_request_id;
  assert_text('request closes after both orders close', l_request_status,
              'CLOSED');

  ------------------------------------------------------------------------------
  -- 07. Void by reversal, reopen derived state, replace, and close again.
  ------------------------------------------------------------------------------

  of_inventory_api.void_receipt(
    p_receipt_id           => l_receipt1_id,
    p_expected_row_version => l_receipt1_version,
    p_reason_text          => 'P07 test reversal of the first partial delivery.',
    p_new_row_version      => l_receipt1_version,
    p_po_status            => l_po_status,
    p_po_row_version       => l_po1_version,
    p_request_status       => l_request_status,
    p_request_row_version  => l_request_version
  );
  assert_text('void reopens first order', l_po_status, 'PARTIALLY_RECEIVED');
  assert_text('void reopens request', l_request_status, 'PARTIALLY_RECEIVED');

  select quantity_on_hand into l_actual_number
    from of_inventory_balances
   where catalog_item_id = l_catalog_item_id
     and location_id = l_location_id;
  assert_number(
    'void subtracts by reversal', l_actual_number, l_baseline_balance + 7
  );

  select count(*) into l_actual_number
    from of_stock_movements
   where related_movement_id is not null
     and receipt_item_id in (
       select id from of_goods_receipt_items
        where goods_receipt_id = l_receipt1_id
     );
  assert_number('one reversal row links to original movement', l_actual_number, 1);

  l_received_at4 := systimestamp;
  of_inventory_api.create_receipt_draft(
    p_po_id               => l_po1_id,
    p_expected_po_version => l_po1_version,
    p_received_at         => l_received_at4,
    p_delivery_reference  => 'P07-R4-' || l_suffix,
    p_notes               => 'Replacement receipt.',
    p_idempotency_key     => 'P07-R4-' || l_suffix,
    p_receipt_id          => l_receipt4_id,
    p_receipt_no          => l_receipt_no,
    p_receipt_row_version => l_receipt4_version
  );

  of_inventory_api.add_receipt_item(
    p_receipt_id           => l_receipt4_id,
    p_expected_row_version => l_receipt4_version,
    p_po_item_id           => l_po1_item_id,
    p_quantity_received    => 3,
    p_quantity_accepted    => 3,
    p_quantity_rejected    => 0,
    p_unit_cost            => 95,
    p_location_id          => l_location_id,
    p_receipt_item_id      => l_receipt_item_id,
    p_new_row_version      => l_receipt4_version
  );

  of_inventory_api.post_receipt(
    p_receipt_id           => l_receipt4_id,
    p_expected_row_version => l_receipt4_version,
    p_idempotency_key      => 'P07-R4-' || l_suffix,
    p_new_row_version      => l_receipt4_version,
    p_po_status            => l_po_status,
    p_po_row_version       => l_po1_version,
    p_request_status       => l_request_status,
    p_request_row_version  => l_request_version
  );
  assert_text('replacement restores first order', l_po_status, 'RECEIVED');
  assert_text('replacement restores request', l_request_status, 'RECEIVED');

  of_inventory_api.create_receipt_draft(
    p_po_id               => l_po1_id,
    p_expected_po_version => 1,
    p_received_at         => l_received_at4,
    p_delivery_reference  => 'P07-R4-' || l_suffix,
    p_notes               => 'Replacement receipt.',
    p_idempotency_key     => 'P07-R4-' || l_suffix,
    p_receipt_id          => l_replay_receipt_id,
    p_receipt_no          => l_replay_receipt_no,
    p_receipt_row_version => l_replay_version
  );
  assert_number('create replay returns same receipt', l_replay_receipt_id,
                l_receipt4_id);
  assert_number('create replay returns current version', l_replay_version,
                l_receipt4_version);

  select quantity_on_hand into l_actual_number
    from of_inventory_balances
   where catalog_item_id = l_catalog_item_id
     and location_id = l_location_id;
  assert_number(
    'replacement restores balance', l_actual_number, l_baseline_balance + 10
  );

  select sum(quantity_delta) into l_actual_number
    from of_stock_movements
   where catalog_item_id = l_catalog_item_id
     and location_id = l_location_id;
  assert_number(
    'ledger and balance reconcile', l_actual_number, l_baseline_ledger + 10
  );

  of_procurement_api.close_order(
    p_po_id               => l_po1_id,
    p_expected_po_version => l_po1_version,
    p_new_po_version      => l_po1_version
  );
  of_procurement_api.close_request(
    p_request_id           => l_request_id,
    p_expected_row_version => l_request_version,
    p_new_row_version      => l_request_version
  );
  select status_code into l_request_status
    from of_purchase_requests where id = l_request_id;
  assert_text('recovered request closes again', l_request_status, 'CLOSED');

  ------------------------------------------------------------------------------
  -- 08. Roll back all test data and prove no test residue remains.
  ------------------------------------------------------------------------------

  select count(*) into l_actual_number
    from of_audit_log
   where entity_type_code = 'PURCHASE_REQUEST'
     and entity_key = l_request_no;
  if l_actual_number > 0 then pass('request actions produced audit evidence');
  else fail('request actions produced no audit evidence'); end if;

  rollback to p07_test_start;

  select count(*) into l_actual_number
    from of_purchase_requests
   where request_no like 'P07T-%';
  assert_number('request residue after rollback', l_actual_number, 0);

  select count(*) into l_actual_number
    from of_goods_receipts
   where receipt_no like 'P07GR-%';
  assert_number('receipt residue after rollback', l_actual_number, 0);

  select count(*) into l_actual_number
    from of_audit_log
   where (entity_type_code = 'PURCHASE_REQUEST' and entity_key like 'P07T-%')
      or (entity_type_code = 'PURCHASE_ORDER' and entity_key like 'P07PO-%')
      or (entity_type_code = 'GOODS_RECEIPT' and entity_key like 'P07GR-%');
  assert_number('audit residue after rollback', l_actual_number, 0);

  dbms_output.put_line('P07 TEST SUITE: PASS');
exception
  when others then
    rollback to p07_test_start;
    dbms_output.put_line('P07 TEST SUITE: FAIL - ' || sqlerrm);
    raise;
end;
/

--------------------------------------------------------------------------------
-- End P07 test. Expected SQL Scripts statements: 1.
--------------------------------------------------------------------------------