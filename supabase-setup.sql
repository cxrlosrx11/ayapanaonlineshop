-- =====================================================================
-- Noir & Gold shop: Supabase setup
-- Paste this whole file into Supabase > SQL Editor > New query, then Run.
-- Before running: create the owner account (README step 3) and change
-- the email on the line marked  >>> CHANGE THIS <<<  near the bottom.
-- It is safe to run more than once.
-- =====================================================================

-- ---------- tables ----------
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  phone text not null default '',
  address text not null default ''
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  price numeric not null check (price >= 0),
  stock integer not null default 0 check (stock >= 0),
  category text not null default '',
  description text not null default '',
  image_path text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.settings (
  id integer primary key check (id = 1),
  shop_name text not null default 'Noir & Gold',
  tagline text not null default 'Bags, wallets and everyday carry.',
  contact text not null default '',
  pay_note text not null default '',
  qr_path text
);
insert into public.settings (id) values (1) on conflict (id) do nothing;

create table if not exists public.orders (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','accepted','completed','declined','cancelled')),
  payment text not null check (payment in ('qr','cod','cop')),
  note text not null default '',
  total numeric not null default 0,
  delivery jsonb not null default '{}'::jsonb,
  paid boolean not null default false,
  paid_at timestamptz,
  pay_ref text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists orders_user_idx on public.orders (user_id);

create table if not exists public.order_items (
  id bigserial primary key,
  order_id text not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  name text not null,
  price numeric not null,
  qty integer not null check (qty > 0)
);
create index if not exists order_items_order_idx on public.order_items (order_id);

-- ---------- who is the owner ----------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

-- ---------- row level security ----------
alter table public.admins enable row level security;      -- no policies: nobody reads it directly
alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.settings enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists profiles_own_select on public.profiles;
drop policy if exists profiles_own_insert on public.profiles;
drop policy if exists profiles_own_update on public.profiles;
create policy profiles_own_select on public.profiles for select using (id = auth.uid());
create policy profiles_own_insert on public.profiles for insert with check (id = auth.uid());
create policy profiles_own_update on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists products_read on public.products;
drop policy if exists products_admin_write on public.products;
create policy products_read on public.products for select using (active or public.is_admin());
create policy products_admin_write on public.products for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists settings_read on public.settings;
drop policy if exists settings_admin_update on public.settings;
create policy settings_read on public.settings for select using (true);
create policy settings_admin_update on public.settings for update
  using (public.is_admin()) with check (public.is_admin());

-- orders can only be read here; every change goes through the functions below
drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders for select
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists order_items_read on public.order_items;
create policy order_items_read on public.order_items for select
  using (exists (select 1 from public.orders o
                 where o.id = order_id and (o.user_id = auth.uid() or public.is_admin())));

-- ---------- order functions ----------
-- Buyer places an order. Prices and the total come from the database, never from the browser.
create or replace function public.place_order(
  p_items jsonb, p_payment text, p_note text, p_delivery jsonb
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id text;
  v_total numeric := 0;
  r record;
  v_prod public.products;
  v_dv jsonb;
begin
  if v_uid is null then raise exception 'Log in to place an order.'; end if;
  if p_payment not in ('qr','cod','cop') then raise exception 'Choose a payment method.'; end if;
  if p_payment = 'qr' and (select qr_path from public.settings where id = 1) is null then
    raise exception 'QR payment is not available yet. Choose another payment method.';
  end if;
  if coalesce(trim(p_delivery->>'name'),'') = ''
     or coalesce(trim(p_delivery->>'phone'),'') = ''
     or coalesce(trim(p_delivery->>'address'),'') = '' then
    raise exception 'Fill in your name, mobile number and address.';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Your cart is empty.';
  end if;

  v_dv := jsonb_build_object(
    'name', left(trim(p_delivery->>'name'), 120),
    'phone', left(trim(p_delivery->>'phone'), 40),
    'address', left(trim(p_delivery->>'address'), 400));

  loop
    v_id := 'NG-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.orders where id = v_id);
  end loop;

  insert into public.orders (id, user_id, payment, note, total, delivery)
  values (v_id, v_uid, p_payment, left(coalesce(p_note,''), 500), 0, v_dv);

  for r in
    select (e->>'product_id')::uuid as pid, greatest((e->>'qty')::int, 1) as qty
    from jsonb_array_elements(p_items) e
  loop
    select * into v_prod from public.products where id = r.pid and active;
    if not found then raise exception 'An item in your cart is no longer available.'; end if;
    if v_prod.stock < r.qty then raise exception 'Not enough stock for %.', v_prod.name; end if;
    insert into public.order_items (order_id, product_id, name, price, qty)
    values (v_id, v_prod.id, v_prod.name, v_prod.price, r.qty);
    v_total := v_total + v_prod.price * r.qty;
  end loop;

  update public.orders set total = v_total where id = v_id;
  return v_id;
end;
$$;

-- Buyer cancels their own pending order.
create or replace function public.cancel_order(p_order text) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.orders set status = 'cancelled', updated_at = now()
  where id = p_order and user_id = auth.uid() and status = 'pending';
  if not found then raise exception 'This order cannot be cancelled.'; end if;
end;
$$;

-- Buyer says they paid by QR.
create or replace function public.report_payment(p_order text, p_ref text) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.orders
  set paid = true, paid_at = now(), pay_ref = left(coalesce(p_ref,''), 80), updated_at = now()
  where id = p_order and user_id = auth.uid() and status = 'pending' and payment = 'qr';
  if not found then raise exception 'This order cannot take a payment report.'; end if;
end;
$$;

-- Owner accepts, declines or completes an order. Accepting takes the items out of stock.
create or replace function public.set_order_status(p_order text, p_status text) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders;
  it record;
  p public.products;
begin
  if not public.is_admin() then raise exception 'Owner access only.'; end if;
  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'Order not found.'; end if;
  if not ((o.status = 'pending' and p_status in ('accepted','declined'))
          or (o.status = 'accepted' and p_status = 'completed')) then
    raise exception 'That change is not allowed for a % order.', o.status;
  end if;
  if p_status = 'accepted' then
    for it in select * from public.order_items where order_id = p_order loop
      select * into p from public.products where id = it.product_id for update;
      if not found or p.stock < it.qty then raise exception 'Not enough stock for %.', it.name; end if;
      update public.products set stock = stock - it.qty, updated_at = now() where id = p.id;
    end loop;
  end if;
  update public.orders set status = p_status, updated_at = now() where id = p_order;
end;
$$;

revoke all on function public.place_order(jsonb, text, text, jsonb) from public;
revoke all on function public.cancel_order(text) from public;
revoke all on function public.report_payment(text, text) from public;
revoke all on function public.set_order_status(text, text) from public;
grant execute on function public.place_order(jsonb, text, text, jsonb) to authenticated;
grant execute on function public.cancel_order(text) to authenticated;
grant execute on function public.report_payment(text, text) to authenticated;
grant execute on function public.set_order_status(text, text) to authenticated;

-- ---------- photo and QR storage ----------
insert into storage.buckets (id, name, public)
values ('shop-images', 'shop-images', true)
on conflict (id) do nothing;

drop policy if exists shop_images_read on storage.objects;
drop policy if exists shop_images_insert on storage.objects;
drop policy if exists shop_images_update on storage.objects;
drop policy if exists shop_images_delete on storage.objects;
create policy shop_images_read on storage.objects for select
  using (bucket_id = 'shop-images');
create policy shop_images_insert on storage.objects for insert
  with check (bucket_id = 'shop-images' and public.is_admin());
create policy shop_images_update on storage.objects for update
  using (bucket_id = 'shop-images' and public.is_admin());
create policy shop_images_delete on storage.objects for delete
  using (bucket_id = 'shop-images' and public.is_admin());

-- ---------- make the owner an admin ----------
do $$
declare
  owner_email text := 'owner@example.com';   -- >>> CHANGE THIS <<< to the owner's email
begin
  insert into public.admins (user_id)
  select id from auth.users where lower(email) = lower(owner_email)
  on conflict do nothing;
  if found then
    raise notice 'Owner set: %', owner_email;
  else
    raise notice 'No change. Either % is already the owner, or no account with that email exists yet.', owner_email;
  end if;
end;
$$;
