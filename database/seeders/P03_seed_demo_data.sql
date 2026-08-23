--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P03 - Synthetic Demo Data
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Safety: Uses only fictional example.invalid identities and TKT-DEMO numbers.
-- Rerun behavior: MERGE preserves row counts and refreshes synthetic time cases.
-- Transaction: All demo changes commit together or roll back together.
--------------------------------------------------------------------------------

declare
  l_anchor          timestamp with local time zone := systimestamp;
  l_reference_count number;
begin
  select count(*)
    into l_reference_count
    from of_sla_policies sp
    join of_service_categories c on c.id = sp.category_id
    join of_priorities p on p.id = sp.priority_id
   where c.code in (
     'ACCOUNT_ACCESS', 'EMAIL_SUPPORT', 'HARDWARE',
     'NETWORK', 'FACILITIES', 'HR_REQUEST'
   )
     and p.code in ('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')
     and sp.effective_from = date '2026-01-01';

  if l_reference_count <> 24 then
    raise_application_error(
      -20032,
      'P03 demo stopped: expected 24 seeded SLA policies, found ' ||
      l_reference_count || '. Run P03_seed_reference_data.sql first.'
    );
  end if;

  ------------------------------------------------------------------------------
  -- 01. Fictional application users
  ------------------------------------------------------------------------------

  merge into of_app_users t
  using (
    select r.username,
           r.email,
           r.display_name,
           d.id department_id,
           l.id location_id,
           r.locale_code,
           l.timezone_name
      from (
        select 'admin.ops' username, 'admin.ops@example.invalid' email,
               'Adam Operations' display_name, 'EXEC' department_code,
               'CAI-HQ' location_code, 'en' locale_code from dual
        union all
        select 'amira.manager', 'amira.manager@example.invalid',
               'Amira Hassan', 'IT', 'CAI-HQ', 'en' from dual
        union all
        select 'omar.agent', 'omar.agent@example.invalid',
               'Omar Nabil', 'IT', 'CAI-HQ', 'en' from dual
        union all
        select 'salma.agent', 'salma.agent@example.invalid',
               'Salma Farouk', 'IT', 'ALX-OFFICE', 'ar' from dual
        union all
        select 'layla.employee', 'layla.employee@example.invalid',
               'Layla Ali', 'HR', 'CAI-HQ', 'ar' from dual
        union all
        select 'youssef.employee', 'youssef.employee@example.invalid',
               'Youssef Adel', 'FIN', 'CAI-HQ', 'en' from dual
        union all
        select 'mariam.employee', 'mariam.employee@example.invalid',
               'Mariam Samir', 'PROC', 'CAI-HQ', 'ar' from dual
        union all
        select 'kareem.manager', 'kareem.manager@example.invalid',
               'Kareem Fathy', 'FIN', 'CAI-HQ', 'en' from dual
        union all
        select 'nader.proc', 'nader.proc@example.invalid',
               'Nader Ibrahim', 'PROC', 'CAI-HQ', 'en' from dual
        union all
        select 'farah.auditor', 'farah.auditor@example.invalid',
               'Farah Amin', 'EXEC', 'DXB-OFFICE', 'en' from dual
        union all
        select 'hassan.facility', 'hassan.facility@example.invalid',
               'Hassan Mostafa', 'FAC', 'CAI-HQ', 'ar' from dual
        union all
        select 'nadia.hr', 'nadia.hr@example.invalid',
               'Nadia Rami', 'HR', 'CAI-HQ', 'en' from dual
      ) r
      join of_departments d on d.code = r.department_code
      join of_locations l on l.code = r.location_code
  ) s
  on (upper(t.username) = upper(s.username))
  when matched then update set
    t.email = s.email,
    t.display_name = s.display_name,
    t.department_id = s.department_id,
    t.location_id = s.location_id,
    t.locale_code = s.locale_code,
    t.timezone_name = s.timezone_name,
    t.is_active = 'Y',
    t.updated_at = l_anchor,
    t.updated_by = 'P03_DEMO'
  when not matched then insert (
    username, email, display_name, department_id, location_id,
    locale_code, timezone_name, is_active, created_by, updated_by
  ) values (
    s.username, s.email, s.display_name, s.department_id, s.location_id,
    s.locale_code, s.timezone_name, 'Y', 'P03_DEMO', 'P03_DEMO'
  );

  ------------------------------------------------------------------------------
  -- 02. User and department management hierarchy
  ------------------------------------------------------------------------------

  merge into of_app_users t
  using (
    select u.id user_id,
           m.id manager_user_id
      from (
        select 'amira.manager' username, 'admin.ops' manager_username from dual
        union all select 'omar.agent', 'amira.manager' from dual
        union all select 'salma.agent', 'amira.manager' from dual
        union all select 'layla.employee', 'nadia.hr' from dual
        union all select 'youssef.employee', 'kareem.manager' from dual
        union all select 'mariam.employee', 'nader.proc' from dual
        union all select 'kareem.manager', 'admin.ops' from dual
        union all select 'nader.proc', 'admin.ops' from dual
        union all select 'farah.auditor', 'admin.ops' from dual
        union all select 'hassan.facility', 'admin.ops' from dual
        union all select 'nadia.hr', 'admin.ops' from dual
      ) r
      join of_app_users u on upper(u.username) = upper(r.username)
      join of_app_users m on upper(m.username) = upper(r.manager_username)
  ) s
  on (t.id = s.user_id)
  when matched then update set
    t.manager_user_id = s.manager_user_id,
    t.updated_at = l_anchor,
    t.updated_by = 'P03_DEMO';

  merge into of_departments t
  using (
    select d.id department_id,
           u.id manager_user_id
      from (
        select 'EXEC' department_code, 'admin.ops' manager_username from dual
        union all select 'IT', 'amira.manager' from dual
        union all select 'HR', 'nadia.hr' from dual
        union all select 'FIN', 'kareem.manager' from dual
        union all select 'PROC', 'nader.proc' from dual
        union all select 'FAC', 'hassan.facility' from dual
      ) r
      join of_departments d on d.code = r.department_code
      join of_app_users u on upper(u.username) = upper(r.manager_username)
  ) s
  on (t.id = s.department_id)
  when matched then update set
    t.manager_user_id = s.manager_user_id,
    t.updated_at = l_anchor,
    t.updated_by = 'P03_DEMO';

  ------------------------------------------------------------------------------
  -- 03. Twenty-four active role grants
  ------------------------------------------------------------------------------

  merge into of_user_roles t
  using (
    select u.id user_id,
           r.id role_id,
           a.id granted_by_user_id
      from (
        select 'admin.ops' username, 'OPERATIONS_ADMIN' role_code from dual
        union all select 'admin.ops', 'EMPLOYEE' from dual
        union all select 'amira.manager', 'MANAGER' from dual
        union all select 'amira.manager', 'SERVICE_AGENT' from dual
        union all select 'amira.manager', 'EMPLOYEE' from dual
        union all select 'omar.agent', 'SERVICE_AGENT' from dual
        union all select 'omar.agent', 'EMPLOYEE' from dual
        union all select 'salma.agent', 'SERVICE_AGENT' from dual
        union all select 'salma.agent', 'EMPLOYEE' from dual
        union all select 'layla.employee', 'EMPLOYEE' from dual
        union all select 'youssef.employee', 'EMPLOYEE' from dual
        union all select 'mariam.employee', 'EMPLOYEE' from dual
        union all select 'kareem.manager', 'MANAGER' from dual
        union all select 'kareem.manager', 'EMPLOYEE' from dual
        union all select 'nader.proc', 'PROCUREMENT_OFFICER' from dual
        union all select 'nader.proc', 'MANAGER' from dual
        union all select 'nader.proc', 'EMPLOYEE' from dual
        union all select 'farah.auditor', 'AUDITOR' from dual
        union all select 'farah.auditor', 'EMPLOYEE' from dual
        union all select 'hassan.facility', 'SERVICE_AGENT' from dual
        union all select 'hassan.facility', 'MANAGER' from dual
        union all select 'hassan.facility', 'EMPLOYEE' from dual
        union all select 'nadia.hr', 'MANAGER' from dual
        union all select 'nadia.hr', 'EMPLOYEE' from dual
      ) x
      join of_app_users u on upper(u.username) = upper(x.username)
      join of_roles r on r.code = x.role_code
      cross join (
        select id
          from of_app_users
         where upper(username) = 'ADMIN.OPS'
      ) a
  ) s
  on (t.user_id = s.user_id and t.role_id = s.role_id)
  when matched then update set
    t.is_active = 'Y',
    t.granted_by_user_id = s.granted_by_user_id,
    t.revoked_at = null,
    t.revoked_by_user_id = null,
    t.updated_at = l_anchor,
    t.updated_by = 'P03_DEMO'
  when not matched then insert (
    user_id, role_id, is_active, granted_at, granted_by_user_id,
    created_by, updated_by
  ) values (
    s.user_id, s.role_id, 'Y', l_anchor, s.granted_by_user_id,
    'P03_DEMO', 'P03_DEMO'
  );

  ------------------------------------------------------------------------------
  -- 04. Twelve demo tickets covering every lifecycle status
  ------------------------------------------------------------------------------

  merge into of_tickets t
  using (
    select r.ticket_no,
           req.id requester_user_id,
           req.department_id requester_department_id,
           c.id category_id,
           p.id priority_id,
           case when r.use_sla = 'Y' then sp.id end sla_policy_id,
           loc.id location_id,
           agent.id assigned_agent_user_id,
           r.status_code,
           r.source_code,
           r.subject,
           r.description,
           l_anchor + numtodsinterval(r.created_hours, 'HOUR') created_at,
           case when r.submitted_hours is not null
                then l_anchor + numtodsinterval(r.submitted_hours, 'HOUR') end submitted_at,
           case when r.triaged_hours is not null
                then l_anchor + numtodsinterval(r.triaged_hours, 'HOUR') end triaged_at,
           case when r.responded_hours is not null
                then l_anchor + numtodsinterval(r.responded_hours, 'HOUR') end first_responded_at,
           case when r.response_due_hours is not null
                then l_anchor + numtodsinterval(r.response_due_hours, 'HOUR') end response_due_at,
           case when r.resolution_due_hours is not null
                then l_anchor + numtodsinterval(r.resolution_due_hours, 'HOUR') end resolution_due_at,
           case when r.waiting_hours is not null
                then l_anchor + numtodsinterval(r.waiting_hours, 'HOUR') end waiting_started_at,
           case when r.resolved_hours is not null
                then l_anchor + numtodsinterval(r.resolved_hours, 'HOUR') end resolved_at,
           case when r.closed_hours is not null
                then l_anchor + numtodsinterval(r.closed_hours, 'HOUR') end closed_at,
           case when r.cancelled_hours is not null
                then l_anchor + numtodsinterval(r.cancelled_hours, 'HOUR') end cancelled_at,
           r.resolution_summary,
           r.closure_reason
      from (
        select 'TKT-DEMO-0001' ticket_no, 'layla.employee' requester_username,
               'ACCOUNT_ACCESS' category_code, 'MEDIUM' priority_code,
               'CAI-HQ' location_code, cast(null as varchar2(255)) agent_username,
               'DRAFT' status_code, 'WEB' source_code,
               'Request access to the analytics portal' subject,
               'Draft request retained to demonstrate an incomplete workflow.' description,
               'N' use_sla, -2 created_hours,
               cast(null as number) submitted_hours,
               cast(null as number) triaged_hours,
               cast(null as number) responded_hours,
               cast(null as number) response_due_hours,
               cast(null as number) resolution_due_hours,
               cast(null as number) waiting_hours,
               cast(null as number) resolved_hours,
               cast(null as number) closed_hours,
               cast(null as number) cancelled_hours,
               cast(null as varchar2(1000)) resolution_summary,
               cast(null as varchar2(1000)) closure_reason
          from dual
        union all
        select 'TKT-DEMO-0002', 'layla.employee', 'EMAIL_SUPPORT', 'MEDIUM',
               'CAI-HQ', null, 'SUBMITTED', 'WEB',
               'Calendar invitations are not arriving',
               'New submitted ticket with comfortable SLA time remaining.',
               'Y', -5.5, -5, null, null, 1, 7, null, null, null, null,
               null, null from dual
        union all
        select 'TKT-DEMO-0003', 'youssef.employee', 'HARDWARE', 'HIGH',
               'CAI-HQ', 'omar.agent', 'TRIAGED', 'WEB',
               'External monitor flickers intermittently',
               'Triaged hardware ticket approaching its resolution deadline.',
               'Y', -4.5, -4, -3.5, null, -3, 1, null, null, null, null,
               null, null from dual
        union all
        select 'TKT-DEMO-0004', 'mariam.employee', 'NETWORK', 'CRITICAL',
               'CAI-HQ', 'omar.agent', 'IN_PROGRESS', 'REST',
               'Warehouse VPN unavailable',
               'Critical network incident whose resolution deadline has passed.',
               'Y', -3.5, -3, -2.8, -2.6, -2.75, -1, null, null, null, null,
               null, null from dual
        union all
        select 'TKT-DEMO-0005', 'layla.employee', 'HARDWARE', 'MEDIUM',
               'ALX-OFFICE', 'salma.agent', 'WAITING_USER', 'WEB',
               'Laptop battery drains quickly',
               'Work paused while the requester supplies a battery health report.',
               'Y', -10.5, -10, -9.5, -8.5, -9, 4, -1, null, null, null,
               null, null from dual
        union all
        select 'TKT-DEMO-0006', 'youssef.employee', 'EMAIL_SUPPORT', 'LOW',
               'CAI-HQ', 'omar.agent', 'RESOLVED', 'WEB',
               'Shared mailbox missing from Outlook',
               'Resolved before the SLA deadline and awaiting requester confirmation.',
               'Y', -30.5, -30, -29, -28, -26, -6, null, -8, null, null,
               'Re-added the shared mailbox permission and refreshed Outlook.', null from dual
        union all
        select 'TKT-DEMO-0007', 'mariam.employee', 'ACCOUNT_ACCESS', 'MEDIUM',
               'CAI-HQ', 'salma.agent', 'CLOSED', 'WEB',
               'Procurement dashboard role required',
               'Completed access request with both resolution and closure evidence.',
               'Y', -50.5, -50, -49.75, -49.5, -49, -42, null, -43, -42.5, null,
               'Granted the approved procurement dashboard role.',
               'Requester confirmed successful access.' from dual
        union all
        select 'TKT-DEMO-0008', 'layla.employee', 'HR_REQUEST', 'LOW',
               'CAI-HQ', null, 'REJECTED', 'WEB',
               'Request unsupported payroll exception',
               'Rejected example with an explanatory business reason.',
               'Y', -24.5, -24, null, null, -20, -1, null, null, null, null,
               null, 'The requested exception is outside the published policy.' from dual
        union all
        select 'TKT-DEMO-0009', 'youssef.employee', 'FACILITIES', 'MEDIUM',
               'CAI-HQ', null, 'CANCELLED', 'WEB',
               'Move desk before team relocation',
               'Cancelled by the requester before operational work began.',
               'N', -4.5, -4, null, null, null, null, null, null, null, -2,
               null, 'Requester cancelled after the seating plan changed.' from dual
        union all
        select 'TKT-DEMO-0010', 'mariam.employee', 'FACILITIES', 'HIGH',
               'CAI-HQ', 'hassan.facility', 'IN_PROGRESS', 'WEB',
               'Meeting room air conditioning is warm',
               'Active facilities work with time remaining before resolution breach.',
               'Y', -2.5, -2, -1.9, -1.7, -1.5, 2, null, null, null, null,
               null, null from dual
        union all
        select 'TKT-DEMO-0011', 'layla.employee', 'NETWORK', 'CRITICAL',
               'ALX-OFFICE', null, 'SUBMITTED', 'REST',
               'Office Wi-Fi authentication failure',
               'Unassigned critical request with a missed response deadline.',
               'Y', -1.5, -1, null, null, -0.75, 0.5, null, null, null, null,
               null, null from dual
        union all
        select 'TKT-DEMO-0012', 'youssef.employee', 'ACCOUNT_ACCESS', 'LOW',
               'CAI-HQ', 'omar.agent', 'IN_PROGRESS', 'WEB',
               'Add reporting permission for month end',
               'Lower-priority work progressing with substantial SLA time remaining.',
               'Y', -5.5, -5, -4.5, -3, -1, 20, null, null, null, null,
               null, null from dual
      ) r
      join of_app_users req
        on upper(req.username) = upper(r.requester_username)
      join of_service_categories c
        on c.code = r.category_code
      join of_priorities p
        on p.code = r.priority_code
      left join of_locations loc
        on loc.code = r.location_code
      left join of_app_users agent
        on upper(agent.username) = upper(r.agent_username)
      left join of_sla_policies sp
        on sp.category_id = c.id
       and sp.priority_id = p.id
       and sp.effective_from = date '2026-01-01'
  ) s
  on (t.ticket_no = s.ticket_no)
  when matched then update set
    t.requester_user_id = s.requester_user_id,
    t.requester_department_id = s.requester_department_id,
    t.category_id = s.category_id,
    t.priority_id = s.priority_id,
    t.sla_policy_id = s.sla_policy_id,
    t.location_id = s.location_id,
    t.assigned_agent_user_id = s.assigned_agent_user_id,
    t.status_code = s.status_code,
    t.source_code = s.source_code,
    t.subject = s.subject,
    t.description = s.description,
    t.submitted_at = s.submitted_at,
    t.triaged_at = s.triaged_at,
    t.first_responded_at = s.first_responded_at,
    t.response_due_at = s.response_due_at,
    t.resolution_due_at = s.resolution_due_at,
    t.waiting_started_at = s.waiting_started_at,
    t.resolved_at = s.resolved_at,
    t.closed_at = s.closed_at,
    t.cancelled_at = s.cancelled_at,
    t.resolution_summary = s.resolution_summary,
    t.closure_reason = s.closure_reason,
    t.row_version = t.row_version,
    t.created_at = s.created_at,
    t.created_by = 'P03_DEMO',
    t.updated_at = l_anchor,
    t.updated_by = 'P03_DEMO'
  when not matched then insert (
    ticket_no, requester_user_id, requester_department_id, category_id,
    priority_id, sla_policy_id, location_id, assigned_agent_user_id,
    status_code, source_code, subject, description, submitted_at, triaged_at,
    first_responded_at, response_due_at, resolution_due_at, waiting_started_at,
    resolved_at, closed_at, cancelled_at, resolution_summary, closure_reason,
    created_at, created_by, updated_at, updated_by
  ) values (
    s.ticket_no, s.requester_user_id, s.requester_department_id, s.category_id,
    s.priority_id, s.sla_policy_id, s.location_id, s.assigned_agent_user_id,
    s.status_code, s.source_code, s.subject, s.description, s.submitted_at,
    s.triaged_at, s.first_responded_at, s.response_due_at, s.resolution_due_at,
    s.waiting_started_at, s.resolved_at, s.closed_at, s.cancelled_at,
    s.resolution_summary, s.closure_reason,
    s.created_at, 'P03_DEMO', l_anchor, 'P03_DEMO'
  );

  ------------------------------------------------------------------------------
  -- 05. Creation history for every demo ticket
  ------------------------------------------------------------------------------

  merge into of_ticket_status_history t
  using (
    select tk.id ticket_id,
           req.id changed_by_user_id,
           req.username changed_by,
           tk.created_at changed_at,
           replace(tk.ticket_no, 'TKT-DEMO-', 'P03-HIST-CREATE-') correlation_id
      from of_tickets tk
      join of_app_users req on req.id = tk.requester_user_id
     where tk.ticket_no like 'TKT-DEMO-%'
  ) s
  on (t.correlation_id = s.correlation_id)
  when matched then update set
    t.ticket_id = s.ticket_id,
    t.from_status_code = null,
    t.to_status_code = 'DRAFT',
    t.changed_at = s.changed_at,
    t.changed_by_user_id = s.changed_by_user_id,
    t.changed_by = s.changed_by,
    t.reason_text = 'Demo ticket created'
  when not matched then insert (
    ticket_id, from_status_code, to_status_code, changed_at,
    changed_by_user_id, changed_by, reason_text, correlation_id
  ) values (
    s.ticket_id, null, 'DRAFT', s.changed_at,
    s.changed_by_user_id, s.changed_by, 'Demo ticket created', s.correlation_id
  );

  ------------------------------------------------------------------------------
  -- 06. Current-state transition evidence for eleven non-draft tickets
  ------------------------------------------------------------------------------

  merge into of_ticket_status_history t
  using (
    select tk.id ticket_id,
           r.from_status_code,
           r.to_status_code,
           l_anchor + numtodsinterval(r.changed_hours, 'HOUR') changed_at,
           u.id changed_by_user_id,
           coalesce(u.username, 'SYSTEM') changed_by,
           r.reason_text,
           r.correlation_id
      from (
        select 'TKT-DEMO-0002' ticket_no, 'DRAFT' from_status_code,
               'SUBMITTED' to_status_code, -5 changed_hours,
               'layla.employee' actor_username,
               'Requester submitted the ticket.' reason_text,
               'P03-HIST-STATE-0002' correlation_id from dual
        union all
        select 'TKT-DEMO-0003', 'SUBMITTED', 'TRIAGED', -3.5,
               'omar.agent', 'Agent validated the hardware category.',
               'P03-HIST-STATE-0003' from dual
        union all
        select 'TKT-DEMO-0004', 'TRIAGED', 'IN_PROGRESS', -2.7,
               'omar.agent', 'Critical incident ownership started.',
               'P03-HIST-STATE-0004' from dual
        union all
        select 'TKT-DEMO-0005', 'IN_PROGRESS', 'WAITING_USER', -1,
               'salma.agent', 'Battery health report requested.',
               'P03-HIST-STATE-0005' from dual
        union all
        select 'TKT-DEMO-0006', 'IN_PROGRESS', 'RESOLVED', -8,
               'omar.agent', 'Mailbox permission restored.',
               'P03-HIST-STATE-0006' from dual
        union all
        select 'TKT-DEMO-0007', 'RESOLVED', 'CLOSED', -42.5,
               'salma.agent', 'Requester confirmed successful access.',
               'P03-HIST-STATE-0007' from dual
        union all
        select 'TKT-DEMO-0008', 'SUBMITTED', 'REJECTED', -12,
               'nadia.hr', 'Request falls outside the published policy.',
               'P03-HIST-STATE-0008' from dual
        union all
        select 'TKT-DEMO-0009', 'DRAFT', 'CANCELLED', -2,
               'youssef.employee', 'Requester cancelled after plan change.',
               'P03-HIST-STATE-0009' from dual
        union all
        select 'TKT-DEMO-0010', 'TRIAGED', 'IN_PROGRESS', -1.8,
               'hassan.facility', 'Facilities engineer began diagnosis.',
               'P03-HIST-STATE-0010' from dual
        union all
        select 'TKT-DEMO-0011', 'DRAFT', 'SUBMITTED', -1,
               'layla.employee', 'Critical connectivity issue submitted.',
               'P03-HIST-STATE-0011' from dual
        union all
        select 'TKT-DEMO-0012', 'TRIAGED', 'IN_PROGRESS', -4,
               'omar.agent', 'Approved access work started.',
               'P03-HIST-STATE-0012' from dual
      ) r
      join of_tickets tk on tk.ticket_no = r.ticket_no
      left join of_app_users u on upper(u.username) = upper(r.actor_username)
  ) s
  on (t.correlation_id = s.correlation_id)
  when matched then update set
    t.ticket_id = s.ticket_id,
    t.from_status_code = s.from_status_code,
    t.to_status_code = s.to_status_code,
    t.changed_at = s.changed_at,
    t.changed_by_user_id = s.changed_by_user_id,
    t.changed_by = s.changed_by,
    t.reason_text = s.reason_text
  when not matched then insert (
    ticket_id, from_status_code, to_status_code, changed_at,
    changed_by_user_id, changed_by, reason_text, correlation_id
  ) values (
    s.ticket_id, s.from_status_code, s.to_status_code, s.changed_at,
    s.changed_by_user_id, s.changed_by, s.reason_text, s.correlation_id
  );

  ------------------------------------------------------------------------------
  -- 07. Ten public/internal/system comments
  ------------------------------------------------------------------------------

  merge into of_ticket_comments t
  using (
    select tk.id ticket_id,
           u.id author_user_id,
           r.visibility_code,
           r.comment_text,
           r.is_system_generated,
           r.comment_key,
           l_anchor + numtodsinterval(r.created_hours, 'HOUR') created_at
      from (
        select 'P03_CMT_001' comment_key, 'TKT-DEMO-0002' ticket_no,
               'layla.employee' author_username, 'PUBLIC' visibility_code,
               'The issue affects invitations from external partners.' comment_text,
               'N' is_system_generated, -4.8 created_hours from dual
        union all
        select 'P03_CMT_002', 'TKT-DEMO-0003', 'omar.agent', 'INTERNAL',
               'Prepare a replacement cable before the desk visit.', 'N', -3.2 from dual
        union all
        select 'P03_CMT_003', 'TKT-DEMO-0004', 'omar.agent', 'PUBLIC',
               'Network engineering is investigating the VPN gateway.', 'N', -2.5 from dual
        union all
        select 'P03_CMT_004', 'TKT-DEMO-0005', 'salma.agent', 'PUBLIC',
               'Please attach the operating-system battery health report.', 'N', -1 from dual
        union all
        select 'P03_CMT_005', 'TKT-DEMO-0005', 'layla.employee', 'PUBLIC',
               'I will provide the report after returning to the office.', 'N', -0.8 from dual
        union all
        select 'P03_CMT_006', 'TKT-DEMO-0006', 'omar.agent', 'PUBLIC',
               'The shared mailbox has been restored. Please verify access.', 'N', -8 from dual
        union all
        select 'P03_CMT_007', 'TKT-DEMO-0007', 'mariam.employee', 'PUBLIC',
               'Confirmed. The procurement dashboard is now visible.', 'N', -42.6 from dual
        union all
        select 'P03_CMT_008', 'TKT-DEMO-0008', 'nadia.hr', 'PUBLIC',
               'Please review the standard payroll policy for supported options.', 'N', -12 from dual
        union all
        select 'P03_CMT_009', 'TKT-DEMO-0010', 'hassan.facility', 'INTERNAL',
               'Temperature reading recorded; checking the local thermostat.', 'N', -1.4 from dual
        union all
        select 'P03_CMT_010', 'TKT-DEMO-0011', null, 'INTERNAL',
               'System marked the response target as breached.', 'Y', -0.7 from dual
      ) r
      join of_tickets tk on tk.ticket_no = r.ticket_no
      left join of_app_users u on upper(u.username) = upper(r.author_username)
  ) s
  on (t.ticket_id = s.ticket_id and t.created_by = s.comment_key)
  when matched then update set
    t.author_user_id = s.author_user_id,
    t.visibility_code = s.visibility_code,
    t.comment_text = s.comment_text,
    t.is_system_generated = s.is_system_generated,
    t.created_at = s.created_at,
    t.updated_at = l_anchor,
    t.updated_by = s.comment_key
  when not matched then insert (
    ticket_id, author_user_id, visibility_code, comment_text,
    is_system_generated, created_at, created_by, updated_at, updated_by
  ) values (
    s.ticket_id, s.author_user_id, s.visibility_code, s.comment_text,
    s.is_system_generated, s.created_at, s.comment_key, l_anchor, s.comment_key
  );

  ------------------------------------------------------------------------------
  -- 08. One active SLA pause for the waiting ticket
  ------------------------------------------------------------------------------

  merge into of_ticket_sla_pauses t
  using (
    select tk.id ticket_id,
           tk.waiting_started_at started_at,
           u.id started_by_user_id
      from of_tickets tk
      join of_app_users u on upper(u.username) = 'SALMA.AGENT'
     where tk.ticket_no = 'TKT-DEMO-0005'
  ) s
  on (t.ticket_id = s.ticket_id and t.ended_at is null)
  when matched then update set
    t.started_at = s.started_at,
    t.reason_code = 'WAITING_USER',
    t.started_by_user_id = s.started_by_user_id
  when not matched then insert (
    ticket_id, started_at, reason_code, started_by_user_id
  ) values (
    s.ticket_id, s.started_at, 'WAITING_USER', s.started_by_user_id
  );

  ------------------------------------------------------------------------------
  -- 09. Retry-safe demo notifications
  ------------------------------------------------------------------------------

  merge into of_notifications t
  using (
    select u.id recipient_user_id,
           r.notification_type_code,
           r.title,
           r.body_text,
           tk.id entity_id,
           r.channel_code,
           r.status_code,
           r.idempotency_key,
           case when r.sent_hours is not null
                then l_anchor + numtodsinterval(r.sent_hours, 'HOUR') end sent_at,
           case when r.read_hours is not null
                then l_anchor + numtodsinterval(r.read_hours, 'HOUR') end read_at,
           r.attempt_count
      from (
        select 'omar.agent' recipient_username,
               'SLA_RESPONSE_BREACH' notification_type_code,
               'Critical ticket missed response target' title,
               'TKT-DEMO-0011 requires immediate triage.' body_text,
               'TKT-DEMO-0011' ticket_no, 'IN_APP' channel_code,
               'PENDING' status_code, 'P03-NOTIFY-0001' idempotency_key,
               cast(null as number) sent_hours, cast(null as number) read_hours,
               0 attempt_count from dual
        union all
        select 'amira.manager', 'SLA_RESOLUTION_BREACH',
               'Critical VPN ticket breached resolution target',
               'TKT-DEMO-0004 is still in progress after its deadline.',
               'TKT-DEMO-0004', 'EMAIL', 'SENT', 'P03-NOTIFY-0002',
               -0.8, null, 1 from dual
        union all
        select 'layla.employee', 'REQUESTER_ACTION_REQUIRED',
               'Battery report required',
               'Please provide the requested battery health report.',
               'TKT-DEMO-0005', 'IN_APP', 'READ', 'P03-NOTIFY-0003',
               -0.5, -0.25, 1 from dual
      ) r
      join of_app_users u on upper(u.username) = upper(r.recipient_username)
      join of_tickets tk on tk.ticket_no = r.ticket_no
  ) s
  on (t.idempotency_key = s.idempotency_key)
  when matched then update set
    t.recipient_user_id = s.recipient_user_id,
    t.notification_type_code = s.notification_type_code,
    t.title = s.title,
    t.body_text = s.body_text,
    t.entity_type_code = 'TICKET',
    t.entity_id = s.entity_id,
    t.channel_code = s.channel_code,
    t.status_code = s.status_code,
    t.sent_at = s.sent_at,
    t.read_at = s.read_at,
    t.attempt_count = s.attempt_count,
    t.last_error_text = null,
    t.updated_at = l_anchor,
    t.updated_by = 'P03_DEMO'
  when not matched then insert (
    recipient_user_id, notification_type_code, title, body_text,
    entity_type_code, entity_id, channel_code, status_code,
    idempotency_key, sent_at, read_at, attempt_count,
    created_by, updated_by
  ) values (
    s.recipient_user_id, s.notification_type_code, s.title, s.body_text,
    'TICKET', s.entity_id, s.channel_code, s.status_code,
    s.idempotency_key, s.sent_at, s.read_at, s.attempt_count,
    'P03_DEMO', 'P03_DEMO'
  );

  ------------------------------------------------------------------------------
  -- 10. SLA event facts linked to notifications
  ------------------------------------------------------------------------------

  merge into of_sla_events t
  using (
    select tk.id ticket_id,
           r.event_type_code,
           case r.deadline_code
             when 'RESPONSE' then tk.response_due_at
             when 'RESOLUTION' then tk.resolution_due_at
           end due_at_snapshot,
           l_anchor + numtodsinterval(r.detected_hours, 'HOUR') detected_at,
           n.id notification_id,
           r.status_code,
           r.correlation_id
      from (
        select 'TKT-DEMO-0004' ticket_no,
               'RESOLUTION_BREACH' event_type_code,
               'RESOLUTION' deadline_code, -0.9 detected_hours,
               'P03-NOTIFY-0002' idempotency_key,
               'NOTIFIED' status_code,
               'P03-SLA-EVENT-0001' correlation_id from dual
        union all
        select 'TKT-DEMO-0011', 'RESPONSE_BREACH', 'RESPONSE', -0.7,
               'P03-NOTIFY-0001', 'DETECTED', 'P03-SLA-EVENT-0002' from dual
      ) r
      join of_tickets tk on tk.ticket_no = r.ticket_no
      join of_notifications n on n.idempotency_key = r.idempotency_key
  ) s
  on (t.correlation_id = s.correlation_id)
  when matched then update set
    t.ticket_id = s.ticket_id,
    t.event_type_code = s.event_type_code,
    t.due_at_snapshot = s.due_at_snapshot,
    t.detected_at = s.detected_at,
    t.notification_id = s.notification_id,
    t.status_code = s.status_code
  when not matched then insert (
    ticket_id, event_type_code, due_at_snapshot, detected_at,
    notification_id, status_code, correlation_id
  ) values (
    s.ticket_id, s.event_type_code, s.due_at_snapshot, s.detected_at,
    s.notification_id, s.status_code, s.correlation_id
  );

  ------------------------------------------------------------------------------
  -- 11. One sanitized audit row per demo ticket
  ------------------------------------------------------------------------------

  merge into of_audit_log t
  using (
    select tk.created_at occurred_at,
           tk.requester_user_id actor_user_id,
           u.username actor_name,
           tk.id entity_id,
           tk.ticket_no entity_key,
           json_object(
             'ticketNo' value tk.ticket_no,
             'status' value tk.status_code
             returning clob
           ) new_values_json,
           replace(tk.ticket_no, 'TKT-DEMO-', 'P03-AUDIT-') correlation_id
      from of_tickets tk
      join of_app_users u on u.id = tk.requester_user_id
     where tk.ticket_no like 'TKT-DEMO-%'
  ) s
  on (t.correlation_id = s.correlation_id)
  when matched then update set
    t.occurred_at = s.occurred_at,
    t.actor_user_id = s.actor_user_id,
    t.actor_name = s.actor_name,
    t.action_code = 'CREATE',
    t.entity_type_code = 'TICKET',
    t.entity_id = s.entity_id,
    t.entity_key = s.entity_key,
    t.old_values_json = null,
    t.new_values_json = s.new_values_json
  when not matched then insert (
    occurred_at, actor_user_id, actor_name, action_code,
    entity_type_code, entity_id, entity_key,
    old_values_json, new_values_json, correlation_id
  ) values (
    s.occurred_at, s.actor_user_id, s.actor_name, 'CREATE',
    'TICKET', s.entity_id, s.entity_key,
    null, s.new_values_json, s.correlation_id
  );

  ------------------------------------------------------------------------------
  -- 12. One handled synthetic error for administrative reports
  ------------------------------------------------------------------------------

  merge into of_error_log t
  using (
    select 'P03-DEMO-ERROR-0001' correlation_id,
           u.id actor_user_id,
           l_anchor - numtodsinterval(6, 'HOUR') occurred_at
      from of_app_users u
     where upper(u.username) = 'ADMIN.OPS'
  ) s
  on (t.correlation_id = s.correlation_id)
  when matched then update set
    t.occurred_at = s.occurred_at,
    t.actor_user_id = s.actor_user_id,
    t.location_code = 'P03_SYNTHETIC_IMPORT',
    t.error_message = 'Synthetic handled error for dashboard demonstration.',
    t.error_stack = 'No real stack: this row is fictional demo evidence.',
    t.backtrace = null,
    t.call_stack = null,
    t.is_handled = 'Y'
  when not matched then insert (
    correlation_id, occurred_at, actor_user_id, location_code,
    error_message, error_stack, is_handled
  ) values (
    s.correlation_id, s.occurred_at, s.actor_user_id,
    'P03_SYNTHETIC_IMPORT',
    'Synthetic handled error for dashboard demonstration.',
    'No real stack: this row is fictional demo evidence.', 'Y'
  );

  commit;
  dbms_output.put_line('P03 demo seed committed successfully.');
exception
  when others then
    rollback;
    dbms_output.put_line('P03 demo seed rolled back: ' || sqlerrm);
    raise;
end;
/

select 'P03_DEMO_COUNTS' as check_name,
       (select count(*) from of_app_users
         where email like '%@example.invalid') users_count,
       (select count(*)
          from of_user_roles ur
          join of_app_users u on u.id = ur.user_id
         where u.email like '%@example.invalid'
           and ur.is_active = 'Y') active_role_grants,
       (select count(*) from of_tickets
         where ticket_no like 'TKT-DEMO-%') tickets_count,
       (select count(*)
          from of_ticket_comments c
          join of_tickets t on t.id = c.ticket_id
         where t.ticket_no like 'TKT-DEMO-%'
           and c.created_by like 'P03_CMT_%') comments_count,
       (select count(*) from of_ticket_status_history
         where correlation_id like 'P03-HIST-%') history_count
  from dual;

--------------------------------------------------------------------------------
-- Expected: USERS=12, ACTIVE_ROLE_GRANTS=24, TICKETS=12,
--           COMMENTS=10, HISTORY=23.
--------------------------------------------------------------------------------
