--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P03 - Seed Idempotency and Reporting View Tests
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Safety: Assertions and SELECT queries only. One expected DML failure is
--         attempted against a read-only view and changes no data.
--------------------------------------------------------------------------------

declare
  l_actual number;

  procedure assert_eq(
    p_label    varchar2,
    p_actual   number,
    p_expected number
  ) is
  begin
    if p_actual <> p_expected then
      raise_application_error(
        -20970,
        p_label || ': expected ' || p_expected || ', found ' || p_actual
      );
    end if;
    dbms_output.put_line('PASS - ' || p_label || ' = ' || p_expected);
  end assert_eq;
begin
  dbms_output.put_line('P03 TEST SUITE: START');

  select count(*) into l_actual
    from of_service_categories
   where code in (
     'ACCOUNT_ACCESS', 'EMAIL_SUPPORT', 'HARDWARE',
     'NETWORK', 'FACILITIES', 'HR_REQUEST'
   );
  assert_eq('seeded service categories', l_actual, 6);

  select count(*) into l_actual
    from of_sla_policies sp
    join of_service_categories c on c.id = sp.category_id
    join of_priorities p on p.id = sp.priority_id
   where c.code in (
     'ACCOUNT_ACCESS', 'EMAIL_SUPPORT', 'HARDWARE',
     'NETWORK', 'FACILITIES', 'HR_REQUEST'
   )
     and p.code in ('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')
     and sp.effective_from = date '2026-01-01';
  assert_eq('complete category-priority SLA matrix', l_actual, 24);

  select count(*) into l_actual
    from of_tickets
   where ticket_no like 'TKT-DEMO-%';
  assert_eq('stable demo ticket count after rerun', l_actual, 12);

  select count(distinct status_code) into l_actual
    from of_tickets
   where ticket_no like 'TKT-DEMO-%';
  assert_eq('ticket lifecycle statuses represented', l_actual, 9);

  select count(*) into l_actual
    from of_v_ticket_details
   where ticket_no like 'TKT-DEMO-%';
  assert_eq('detail view reconciles to demo tickets', l_actual, 12);

  select count(*) into l_actual
    from of_v_sla_queue
   where ticket_no like 'TKT-DEMO-%';
  assert_eq('SLA queue open due-backed tickets', l_actual, 7);

  select count(*) into l_actual
    from (
      select queue_rank,
             row_number() over (order by queue_rank) expected_rank
        from of_v_sla_queue
       where ticket_no like 'TKT-DEMO-%'
    )
   where queue_rank <> expected_rank;
  assert_eq('SLA queue ranks are contiguous', l_actual, 0);

  select sum(total_tickets) into l_actual
    from of_v_service_dashboard;
  assert_eq('dashboard reconciles to all base tickets', l_actual, 12);

  select sum(active_role_count) into l_actual
    from of_v_user_access
   where email like '%@example.invalid';
  assert_eq('user-access view active role grants', l_actual, 24);

  select count(*) into l_actual
    from of_v_ticket_timeline
   where ticket_no like 'TKT-DEMO-%';
  assert_eq('unified timeline event count', l_actual, 36);

  begin
    update of_v_ticket_details
       set subject = 'This update must fail'
     where ticket_no = 'TKT-DEMO-0001';

    raise_application_error(-20971, 'read-only view accepted an update');
  exception
    when others then
      if sqlcode = -20971 then
        raise;
      elsif sqlcode <> -42399 then
        raise_application_error(
          -20972,
          'unexpected read-only-view error: ' || sqlerrm
        );
      else
        dbms_output.put_line('PASS - reporting view rejected DML');
      end if;
  end;

  dbms_output.put_line('P03 TEST SUITE: PASS');
exception
  when others then
    dbms_output.put_line('P03 TEST SUITE: FAIL - ' || sqlerrm);
    raise;
end;
/

--------------------------------------------------------------------------------
-- Learning query 1: joined ticket details
--------------------------------------------------------------------------------

select ticket_no,
       status_code,
       requester_display_name,
       category_name,
       priority_name,
       assigned_agent_name,
       resolution_health_code
  from of_v_ticket_details
 where ticket_no like 'TKT-DEMO-%'
 order by ticket_no;

--------------------------------------------------------------------------------
-- Learning query 2: aggregate dashboard
--------------------------------------------------------------------------------

select category_code,
       total_tickets,
       open_tickets,
       breached_tickets,
       at_risk_tickets,
       avg_resolution_hours
  from of_v_service_dashboard
 order by category_code;

--------------------------------------------------------------------------------
-- Learning query 3: analytic SLA ranking
--------------------------------------------------------------------------------

select queue_rank,
       ticket_no,
       priority_code,
       resolution_health_code,
       minutes_to_resolution_due,
       health_group_count
  from of_v_sla_queue
 order by queue_rank;

--------------------------------------------------------------------------------
-- Learning query 4: LISTAGG role summary
--------------------------------------------------------------------------------

select username,
       department_code,
       active_role_count,
       active_role_codes
  from of_v_user_access
 where email like '%@example.invalid'
 order by username;

--------------------------------------------------------------------------------
-- Learning query 5: one unified chronology
--------------------------------------------------------------------------------

select ticket_no,
       event_type_code,
       event_at,
       actor_name,
       visibility_code,
       event_summary,
       event_detail
  from of_v_ticket_timeline
 where ticket_no = 'TKT-DEMO-0005'
 order by event_at, event_type_code, event_id;

--------------------------------------------------------------------------------
-- End P03 test suite.
--------------------------------------------------------------------------------
