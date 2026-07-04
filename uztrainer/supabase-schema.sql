-- ============================================================
-- Схема для личного кабинета компании (Supabase / Postgres)
-- Выполнить целиком в Supabase → SQL Editor → New query → Run
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- таблицы ----------

create table companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text unique not null,
  created_at timestamptz default now()
);

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid references companies(id) on delete cascade not null,
  role text not null check (role in ('admin','employee')),
  full_name text,
  created_at timestamptz default now()
);

create table scripts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade not null,
  title text not null,
  sphere text,
  audience text default 'b2c' check (audience in ('b2c','b2b')),
  content text not null,
  created_at timestamptz default now()
);

-- ---------- функция для поиска компании по коду приглашения ----------
-- (SECURITY DEFINER — обходит RLS, но отдаёт только id компании, не весь список)

create or replace function get_company_by_invite(code text)
returns uuid
language sql
security definer
set search_path = public
as $$
  select id from companies where invite_code = upper(code) limit 1;
$$;

-- ---------- вспомогательные функции для политик ----------
-- (SECURITY DEFINER обходит RLS при внутреннем поиске — без этого
-- политика на profiles, которая сама делает подзапрос к profiles,
-- зациклится: infinite recursion detected in policy)

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

-- ---------- RLS ----------

alter table companies enable row level security;
alter table profiles enable row level security;
alter table scripts enable row level security;

-- companies: видно только свою компанию; создать компанию может любой авторизованный (при регистрации админа)
create policy "companies select own" on companies
  for select using ( id = get_my_company_id() );

create policy "companies insert any authenticated" on companies
  for insert with check (auth.uid() is not null);

-- profiles: видно всех сотрудников своей компании; редактировать/создавать можно только свою запись
create policy "profiles select same company" on profiles
  for select using ( company_id = get_my_company_id() );

create policy "profiles insert own" on profiles
  for insert with check (id = auth.uid());

create policy "profiles update own" on profiles
  for update using (id = auth.uid());

-- scripts: видно все скрипты своей компании; изменять/добавлять/удалять может только admin своей компании
create policy "scripts select same company" on scripts
  for select using ( company_id = get_my_company_id() );

create policy "scripts admin insert" on scripts
  for insert with check ( company_id = get_my_company_id() and get_my_role() = 'admin' );

create policy "scripts admin update" on scripts
  for update using ( company_id = get_my_company_id() and get_my_role() = 'admin' );

create policy "scripts admin delete" on scripts
  for delete using ( company_id = get_my_company_id() and get_my_role() = 'admin' );

-- разрешаем анонимному/авторизованному клиенту вызывать функцию поиска по коду
grant execute on function get_company_by_invite(text) to anon, authenticated;
