--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P09 - Employee Self-Service Database Rollback
-- IMPORTANT: Export the APEX application, then remove Pages 11-19 and restore
-- Page 10's P08 placeholder before running this script.
-- Destructive scope: Drops only the five P09 read-only views.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 00. Later-database-dependency guard
--------------------------------------------------------------------------------

declare
  l_dependency_count number;
begin
  select count(*)
    into l_dependency_count
    from user_dependencies
   where referenced_name in (
     'OF_V_MY_TICKETS', 'OF_V_MY_TICKET_TIMELINE', 'OF_V_MY_ASSETS',
     'OF_V_MY_PURCHASE_REQUESTS', 'OF_V_MY_PURCHASE_REQUEST_ITEMS'
   )
     and name not in (
       'OF_V_MY_TICKETS', 'OF_V_MY_TICKET_TIMELINE', 'OF_V_MY_ASSETS',
       'OF_V_MY_PURCHASE_REQUESTS', 'OF_V_MY_PURCHASE_REQUEST_ITEMS'
     );

  if l_dependency_count > 0 then
    raise_application_error(
      -20509,
      'P09 rollback stopped: ' || l_dependency_count ||
      ' later database dependency row(s) reference P09 views.'
    );
  end if;

  dbms_output.put_line(
    'P09 dependency guard passed. Confirm the APEX pages were removed first.'
  );
end;
/

--------------------------------------------------------------------------------
-- 01. Drop the P09 views in dependency order; tolerate a partial installation.
--------------------------------------------------------------------------------

declare
  procedure drop_view_if_present(p_view_name in varchar2) is
    l_count number;
  begin
    select count(*)
      into l_count
      from user_views
     where view_name = upper(p_view_name);

    if l_count = 1 then
      execute immediate
        'drop view ' || dbms_assert.simple_sql_name(upper(p_view_name));
      dbms_output.put_line('Dropped view ' || upper(p_view_name));
    end if;
  end drop_view_if_present;
begin
  drop_view_if_present('OF_V_MY_TICKET_TIMELINE');
  drop_view_if_present('OF_V_MY_PURCHASE_REQUEST_ITEMS');
  drop_view_if_present('OF_V_MY_PURCHASE_REQUESTS');
  drop_view_if_present('OF_V_MY_ASSETS');
  drop_view_if_present('OF_V_MY_TICKETS');
end;
/

--------------------------------------------------------------------------------
-- 02. Rollback evidence
-- Expected: no rows.
--------------------------------------------------------------------------------

select object_name,
       object_type,
       status
  from user_objects
 where object_name in (
   'OF_V_MY_TICKETS', 'OF_V_MY_TICKET_TIMELINE', 'OF_V_MY_ASSETS',
   'OF_V_MY_PURCHASE_REQUESTS', 'OF_V_MY_PURCHASE_REQUEST_ITEMS'
 )
 order by object_name;

--------------------------------------------------------------------------------
-- End P09 rollback. Expected SQL Scripts statements: 3.
--------------------------------------------------------------------------------
