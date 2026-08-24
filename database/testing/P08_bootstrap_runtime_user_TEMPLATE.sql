--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P08 - Bootstrap One Authenticated APEX User
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- IMPORTANT: First run the new application and copy the exact APP_USER value.
-- Edit only the three constants marked EDIT BEFORE RUNNING.
-- No password is stored in the business schema.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 00. Create/update the P08 bootstrap identity and grant two additive roles
--------------------------------------------------------------------------------

declare
  -- EDIT BEFORE RUNNING: exact value displayed by &APP_USER. in the runtime app.
  l_apex_username constant varchar2(255 char) := 'REPLACE_WITH_EXACT_APP_USER';

  -- EDIT BEFORE RUNNING: business display name, not a password or secret.
  l_display_name constant varchar2(200 char) := 'REPLACE_WITH_DISPLAY_NAME';

  -- EDIT BEFORE RUNNING: email used for this business identity.
  l_email constant varchar2(255 char) := 'REPLACE_WITH_EMAIL';

  l_department_id number;
  l_location_id   number;
  l_user_id       number;
  l_role_count    number;
  l_bootstrap_count number;
  l_existing_by   of_app_users.created_by%type;
begin
  if l_apex_username = 'REPLACE_WITH_EXACT_APP_USER'
     or l_display_name = 'REPLACE_WITH_DISPLAY_NAME'
     or l_email = 'REPLACE_WITH_EMAIL' then
    raise_application_error(
      -20483,
      'P08 bootstrap stopped: edit all three marked constants first.'
    );
  end if;

  if trim(l_apex_username) is null
     or trim(l_display_name) is null
     or trim(l_email) is null then
    raise_application_error(
      -20483,
      'P08 bootstrap stopped: username, display name, and email are required.'
    );
  end if;

  select id into l_department_id
    from of_departments
   where code = 'EXEC'
     and is_active = 'Y';

  select id into l_location_id
    from of_locations
   where code = 'CAI-HQ'
     and is_active = 'Y';

  select count(*)
    into l_role_count
    from of_roles
   where code in ('EMPLOYEE', 'OPERATIONS_ADMIN')
     and is_active = 'Y';

  if l_role_count <> 2 then
    raise_application_error(
      -20485,
      'P08 bootstrap stopped: expected active EMPLOYEE and ' ||
      'OPERATIONS_ADMIN roles.'
    );
  end if;

  select count(*)
    into l_bootstrap_count
    from of_app_users
   where created_by = 'P08_BOOTSTRAP';

  begin
    select id, created_by
      into l_user_id, l_existing_by
      from of_app_users
     where upper(trim(username)) = upper(trim(l_apex_username));

    if l_existing_by <> 'P08_BOOTSTRAP' then
      raise_application_error(
        -20484,
        'P08 bootstrap stopped: APP_USER is already mapped to a non-P08 ' ||
        'business identity. Review it; do not silently elevate it.'
      );
    end if;

    update of_app_users
       set username = trim(l_apex_username),
           email = trim(l_email),
           display_name = trim(l_display_name),
           department_id = l_department_id,
           location_id = l_location_id,
           locale_code = 'en',
           timezone_name = 'Africa/Cairo',
           is_active = 'Y',
           row_version = row_version + 1,
           updated_at = systimestamp,
           updated_by = 'P08_BOOTSTRAP'
     where id = l_user_id;
  exception
    when no_data_found then
      if l_bootstrap_count > 0 then
        raise_application_error(
          -20484,
          'P08 bootstrap stopped: a different P08 bootstrap identity ' ||
          'already exists. Review it instead of creating a second one.'
        );
      end if;

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
        trim(l_apex_username),
        trim(l_email),
        trim(l_display_name),
        l_department_id,
        l_location_id,
        'en',
        'Africa/Cairo',
        'Y',
        'P08_BOOTSTRAP',
        'P08_BOOTSTRAP'
      ) returning id into l_user_id;
  end;

  for r in (
    select id
      from of_roles
     where code in ('EMPLOYEE', 'OPERATIONS_ADMIN')
       and is_active = 'Y'
  ) loop
    merge into of_user_roles t
    using (
      select l_user_id user_id, r.id role_id from dual
    ) s
    on (t.user_id = s.user_id and t.role_id = s.role_id)
    when matched then update set
      t.is_active = 'Y',
      t.granted_at = systimestamp,
      t.granted_by_user_id = l_user_id,
      t.revoked_at = null,
      t.revoked_by_user_id = null,
      t.updated_at = systimestamp,
      t.updated_by = 'P08_BOOTSTRAP'
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
      l_user_id,
      'P08_BOOTSTRAP',
      'P08_BOOTSTRAP'
    );
  end loop;

  commit;

  dbms_output.put_line(
    'P08 bootstrap mapping created for ' || upper(trim(l_apex_username)) || '.'
  );
end;
/

--------------------------------------------------------------------------------
-- 01. Bootstrap identity evidence
-- Expected: 1 row, ACTIVE.
--------------------------------------------------------------------------------

select id,
       username,
       display_name,
       locale_code,
       timezone_name,
       is_active
  from of_app_users
 where created_by = 'P08_BOOTSTRAP'
 order by id;

--------------------------------------------------------------------------------
-- 02. Bootstrap role evidence
-- Expected: EMPLOYEE and OPERATIONS_ADMIN, both active.
--------------------------------------------------------------------------------

select u.username,
       r.code role_code,
       ur.is_active
  from of_app_users u
  join of_user_roles ur on ur.user_id = u.id
  join of_roles r on r.id = ur.role_id
 where u.created_by = 'P08_BOOTSTRAP'
   and r.code in ('EMPLOYEE', 'OPERATIONS_ADMIN')
 order by r.code;

--------------------------------------------------------------------------------
-- End P08 bootstrap. Expected SQL Scripts statements: 3.
--------------------------------------------------------------------------------
