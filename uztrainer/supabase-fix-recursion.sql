-- ============================================================
-- ФИКС: infinite recursion detected in policy for relation "profiles"
-- Причина: политики на profiles/companies/scripts сами делали
-- подзапрос к profiles, из-за чего RLS-проверка зацикливалась.
-- Решение: вынести получение company_id/role в SECURITY DEFINER
-- функции, которые обходят RLS при внутреннем поиске.
-- Выполнить целиком в Supabase → SQL Editor → Run
-- ============================================================

-- ---------- вспомогательные функции ----------

create or replace function get_my_company_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select company_id from profiles where id = auth.uid();
$$;

create or replace function get_my_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select role from profiles where id = auth.uid();
$$;

grant execute on function get_my_company_id() to anon, authenticated;
grant execute on function get_my_role() to anon, authenticated;

-- ---------- пересоздаём политики через функции ----------

drop policy if exists "companies select own" on companies;
create policy "companies select own" on companies
  for select using ( id = get_my_company_id() );

drop policy if exists "profiles select same company" on profiles;
create policy "profiles select same company" on profiles
  for select using ( company_id = get_my_company_id() );

drop policy if exists "scripts select same company" on scripts;
create policy "scripts select same company" on scripts
  for select using ( company_id = get_my_company_id() );

drop policy if exists "scripts admin insert" on scripts;
create policy "scripts admin insert" on scripts
  for insert with check ( company_id = get_my_company_id() and get_my_role() = 'admin' );

drop policy if exists "scripts admin update" on scripts;
create policy "scripts admin update" on scripts
  for update using ( company_id = get_my_company_id() and get_my_role() = 'admin' );

drop policy if exists "scripts admin delete" on scripts;
create policy "scripts admin delete" on scripts
  for delete using ( company_id = get_my_company_id() and get_my_role() = 'admin' );
