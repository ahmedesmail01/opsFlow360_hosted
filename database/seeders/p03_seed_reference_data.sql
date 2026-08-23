--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P03 - Deterministic Reference Data
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Safety: Requires the complete P02 schema. MERGE makes reruns idempotent.
-- Transaction: All reference changes commit together or roll back together.
--------------------------------------------------------------------------------

declare
  l_table_count number;
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

  if l_table_count <> 17 then
    raise_application_error(
      -20031,
      'P03 stopped: expected 17 P02 tables, found ' || l_table_count || '.'
    );
  end if;

  ------------------------------------------------------------------------------
  -- 01. Departments
  ------------------------------------------------------------------------------

  merge into of_departments t
  using (
    select 'EXEC' code, 'Executive Office' name,
           'Executive sponsorship, governance, and audit coordination.' description
      from dual
    union all
    select 'IT', 'Information Technology',
           'Corporate systems, accounts, devices, networks, and service desk.'
      from dual
    union all
    select 'HR', 'People and Culture',
           'Employee services, policies, onboarding, and people operations.'
      from dual
    union all
    select 'FIN', 'Finance',
           'Financial control, budgeting, reporting, and payment operations.'
      from dual
    union all
    select 'PROC', 'Procurement',
           'Sourcing, purchase orders, suppliers, and commercial coordination.'
      from dual
    union all
    select 'FAC', 'Facilities',
           'Workplace access, maintenance, utilities, and physical operations.'
      from dual
  ) s
  on (t.code = s.code)
  when matched then update set
    t.name = s.name,
    t.description = s.description,
    t.is_active = 'Y',
    t.updated_at = systimestamp,
    t.updated_by = 'P03_SEED'
  when not matched then insert (
    code, name, description, is_active, created_by, updated_by
  ) values (
    s.code, s.name, s.description, 'Y', 'P03_SEED', 'P03_SEED'
  );

  ------------------------------------------------------------------------------
  -- 02. Locations
  ------------------------------------------------------------------------------

  merge into of_locations t
  using (
    select 'CAI-HQ' code, 'Cairo Headquarters' name,
           'New Cairo, Cairo, Egypt' address_text,
           'EG' country_code, 'Africa/Cairo' timezone_name
      from dual
    union all
    select 'CAI-WH', 'Cairo Operations Warehouse',
           'Nasr City, Cairo, Egypt', 'EG', 'Africa/Cairo'
      from dual
    union all
    select 'ALX-OFFICE', 'Alexandria Office',
           'Smouha, Alexandria, Egypt', 'EG', 'Africa/Cairo'
      from dual
    union all
    select 'DXB-OFFICE', 'Dubai Office',
           'Business Bay, Dubai, United Arab Emirates', 'AE', 'Asia/Dubai'
      from dual
  ) s
  on (t.code = s.code)
  when matched then update set
    t.name = s.name,
    t.address_text = s.address_text,
    t.country_code = s.country_code,
    t.timezone_name = s.timezone_name,
    t.is_active = 'Y',
    t.updated_at = systimestamp,
    t.updated_by = 'P03_SEED'
  when not matched then insert (
    code, name, address_text, country_code, timezone_name,
    is_active, created_by, updated_by
  ) values (
    s.code, s.name, s.address_text, s.country_code, s.timezone_name,
    'Y', 'P03_SEED', 'P03_SEED'
  );

  ------------------------------------------------------------------------------
  -- 03. Stable application roles
  ------------------------------------------------------------------------------

  merge into of_roles t
  using (
    select 'EMPLOYEE' code, 'Employee' name,
           'Creates and follows personal service and procurement requests.' description
      from dual
    union all
    select 'SERVICE_AGENT', 'Service Agent',
           'Triages, owns, communicates on, and resolves service tickets.'
      from dual
    union all
    select 'PROCUREMENT_OFFICER', 'Procurement Officer',
           'Reviews approved requests and manages sourcing and ordering.'
      from dual
    union all
    select 'MANAGER', 'Manager',
           'Approves scoped requests and views department operations.'
      from dual
    union all
    select 'OPERATIONS_ADMIN', 'Operations Administrator',
           'Configures the platform and administers operational reference data.'
      from dual
    union all
    select 'AUDITOR', 'Auditor',
           'Reviews read-only operational, security, and audit evidence.'
      from dual
  ) s
  on (t.code = s.code)
  when matched then update set
    t.name = s.name,
    t.description = s.description,
    t.is_active = 'Y',
    t.updated_at = systimestamp,
    t.updated_by = 'P03_SEED'
  when not matched then insert (
    code, name, description, is_active, created_by, updated_by
  ) values (
    s.code, s.name, s.description, 'Y', 'P03_SEED', 'P03_SEED'
  );

  ------------------------------------------------------------------------------
  -- 04. Non-secret application settings
  ------------------------------------------------------------------------------

  merge into of_app_settings t
  using (
    select 'DEFAULT_LOCALE' setting_code, 'TEXT' data_type_code,
           'en' setting_value,
           'Default UI locale for a user without a stored preference.' description
      from dual
    union all
    select 'DEFAULT_TIMEZONE', 'TEXT', 'Africa/Cairo',
           'Default named time zone for business display and demo users.'
      from dual
    union all
    select 'TICKET_PREFIX', 'TEXT', 'TKT',
           'Stable prefix used by the future ticket-number generator.'
      from dual
    union all
    select 'SLA_WARNING_PERCENT', 'NUMBER', '80',
           'Default percentage of an SLA window at which a warning is raised.'
      from dual
    union all
    select 'ENABLE_EMAIL_NOTIFICATIONS', 'BOOLEAN', 'Y',
           'Business switch for email delivery; contains no credential.'
      from dual
  ) s
  on (t.setting_code = s.setting_code)
  when matched then update set
    t.data_type_code = s.data_type_code,
    t.setting_value = s.setting_value,
    t.description = s.description,
    t.is_sensitive = 'N',
    t.row_version = t.row_version,
    t.updated_at = systimestamp,
    t.updated_by = 'P03_SEED'
  when not matched then insert (
    setting_code, data_type_code, setting_value, description,
    is_sensitive, created_by, updated_by
  ) values (
    s.setting_code, s.data_type_code, s.setting_value, s.description,
    'N', 'P03_SEED', 'P03_SEED'
  );

  ------------------------------------------------------------------------------
  -- 05. Ticket priorities
  ------------------------------------------------------------------------------

  merge into of_priorities t
  using (
    select 'CRITICAL' code, 'Critical' name, 10 sort_order, 1 severity_rank
      from dual
    union all
    select 'HIGH', 'High', 20, 2 from dual
    union all
    select 'MEDIUM', 'Medium', 30, 3 from dual
    union all
    select 'LOW', 'Low', 40, 4 from dual
  ) s
  on (t.code = s.code)
  when matched then update set
    t.name = s.name,
    t.sort_order = s.sort_order,
    t.severity_rank = s.severity_rank,
    t.is_active = 'Y',
    t.updated_at = systimestamp,
    t.updated_by = 'P03_SEED'
  when not matched then insert (
    code, name, sort_order, severity_rank, is_active, created_by, updated_by
  ) values (
    s.code, s.name, s.sort_order, s.severity_rank,
    'Y', 'P03_SEED', 'P03_SEED'
  );

  ------------------------------------------------------------------------------
  -- 06. Service catalogue
  ------------------------------------------------------------------------------

  merge into of_service_categories t
  using (
    select r.code,
           r.name,
           r.description,
           d.id owner_department_id,
           p.id default_priority_id,
           r.requires_location
      from (
        select 'ACCOUNT_ACCESS' code, 'Account and Access' name,
               'Request a new account, permission, or access correction.' description,
               'IT' department_code, 'MEDIUM' priority_code,
               'N' requires_location
          from dual
        union all
        select 'EMAIL_SUPPORT', 'Email Support',
               'Report mailbox, delivery, calendar, or collaboration problems.',
               'IT', 'MEDIUM', 'N' from dual
        union all
        select 'HARDWARE', 'Computer Hardware',
               'Report a laptop, desktop, monitor, printer, or peripheral issue.',
               'IT', 'HIGH', 'Y' from dual
        union all
        select 'NETWORK', 'Network and Connectivity',
               'Report office internet, Wi-Fi, VPN, or network access problems.',
               'IT', 'HIGH', 'Y' from dual
        union all
        select 'FACILITIES', 'Facilities and Workplace',
               'Request workplace maintenance, access, utilities, or room support.',
               'FAC', 'MEDIUM', 'Y' from dual
        union all
        select 'HR_REQUEST', 'People Services',
               'Ask for an employment letter, policy clarification, or HR service.',
               'HR', 'LOW', 'N' from dual
      ) r
      join of_departments d
        on d.code = r.department_code
      join of_priorities p
        on p.code = r.priority_code
  ) s
  on (t.code = s.code)
  when matched then update set
    t.name = s.name,
    t.description = s.description,
    t.owner_department_id = s.owner_department_id,
    t.default_priority_id = s.default_priority_id,
    t.requires_location = s.requires_location,
    t.is_active = 'Y',
    t.updated_at = systimestamp,
    t.updated_by = 'P03_SEED'
  when not matched then insert (
    code, name, description, owner_department_id, default_priority_id,
    requires_location, is_active, created_by, updated_by
  ) values (
    s.code, s.name, s.description, s.owner_department_id,
    s.default_priority_id, s.requires_location,
    'Y', 'P03_SEED', 'P03_SEED'
  );

  ------------------------------------------------------------------------------
  -- 07. Effective-dated SLA matrix: 6 categories x 4 priorities = 24 rows
  ------------------------------------------------------------------------------

  merge into of_sla_policies t
  using (
    select c.id category_id,
           p.id priority_id,
           case p.code
             when 'CRITICAL' then 15
             when 'HIGH' then 30
             when 'MEDIUM' then 60
             when 'LOW' then 240
           end response_minutes,
           case p.code
             when 'CRITICAL' then 120
             when 'HIGH' then 240
             when 'MEDIUM' then 480
             when 'LOW' then 1440
           end resolution_minutes,
           80 warning_percent,
           'Y' pause_when_waiting_user,
           date '2026-01-01' effective_from
      from of_service_categories c
      cross join of_priorities p
     where c.code in (
       'ACCOUNT_ACCESS', 'EMAIL_SUPPORT', 'HARDWARE',
       'NETWORK', 'FACILITIES', 'HR_REQUEST'
     )
       and p.code in ('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')
  ) s
  on (
    t.category_id = s.category_id
    and t.priority_id = s.priority_id
    and t.effective_from = s.effective_from
  )
  when matched then update set
    t.response_minutes = s.response_minutes,
    t.resolution_minutes = s.resolution_minutes,
    t.warning_percent = s.warning_percent,
    t.pause_when_waiting_user = s.pause_when_waiting_user,
    t.effective_to = null,
    t.is_active = 'Y',
    t.row_version = t.row_version,
    t.updated_at = systimestamp,
    t.updated_by = 'P03_SEED'
  when not matched then insert (
    category_id, priority_id, response_minutes, resolution_minutes,
    warning_percent, pause_when_waiting_user, effective_from,
    effective_to, is_active, created_by, updated_by
  ) values (
    s.category_id, s.priority_id, s.response_minutes, s.resolution_minutes,
    s.warning_percent, s.pause_when_waiting_user, s.effective_from,
    null, 'Y', 'P03_SEED', 'P03_SEED'
  );

  commit;
  dbms_output.put_line('P03 reference seed committed successfully.');
exception
  when others then
    rollback;
    dbms_output.put_line('P03 reference seed rolled back: ' || sqlerrm);
    raise;
end;
/

select 'P03_REFERENCE_COUNTS' as check_name,
       (select count(*) from of_departments
         where code in ('EXEC', 'IT', 'HR', 'FIN', 'PROC', 'FAC')) departments,
       (select count(*) from of_locations
         where code in ('CAI-HQ', 'CAI-WH', 'ALX-OFFICE', 'DXB-OFFICE')) locations,
       (select count(*) from of_roles) roles,
       (select count(*) from of_priorities
         where code in ('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')) priorities,
       (select count(*) from of_service_categories
         where code in (
           'ACCOUNT_ACCESS', 'EMAIL_SUPPORT', 'HARDWARE',
           'NETWORK', 'FACILITIES', 'HR_REQUEST'
         )) categories,
       (select count(*)
          from of_sla_policies sp
          join of_service_categories c on c.id = sp.category_id
          join of_priorities p on p.id = sp.priority_id
         where c.code in (
           'ACCOUNT_ACCESS', 'EMAIL_SUPPORT', 'HARDWARE',
           'NETWORK', 'FACILITIES', 'HR_REQUEST'
         )
           and p.code in ('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')
           and sp.effective_from = date '2026-01-01') sla_policies
  from dual;

--------------------------------------------------------------------------------
-- Expected: DEPARTMENTS=6, LOCATIONS=4, ROLES=6, PRIORITIES=4,
--           CATEGORIES=6, SLA_POLICIES=24.
--------------------------------------------------------------------------------
