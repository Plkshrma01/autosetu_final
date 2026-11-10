-- AUTOSETU for Supabase: paste ALL of this into Supabase > SQL Editor > Run
create table profiles(id uuid primary key references auth.users on delete cascade,name text,phone text,
 role text not null default 'passenger' check(role in('passenger','driver','admin')),vehicle text,active bool default true,
 verified bool default false,online bool default false,lat float8,lng float8,created timestamptz default now());
create table rides(id bigint generated always as identity primary key,passenger_id uuid not null default auth.uid() references profiles(id),
 driver_id uuid references profiles(id),pname text,plat float8 not null,plng float8 not null,paddr text,dlat float8 not null,dlng float8 not null,daddr text,
 status text not null default 'requested' check(status in('requested','accepted','arrived','started','completed','cancelled')),
 fare int,rating int check(rating between 1 and 5),review text,created timestamptz default now());
create table rejections(ride_id bigint references rides on delete cascade,driver_id uuid default auth.uid() references profiles(id),primary key(ride_id,driver_id));
create table reports(id bigint generated always as identity primary key,user_id uuid default auth.uid() references profiles(id),text text,created timestamptz default now());

create function is_admin() returns bool language sql security definer stable set search_path=public as $$select exists(select 1 from profiles where id=auth.uid() and role='admin' and active)$$;
create function is_vdriver() returns bool language sql security definer stable set search_path=public as $$select exists(select 1 from profiles where id=auth.uid() and role='driver' and verified and active)$$;
-- role can only ever be passenger/driver from signup; admin is granted only via SQL editor
create function new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into profiles(id,name,phone,vehicle,role) values(new.id,new.raw_user_meta_data->>'name',new.raw_user_meta_data->>'phone',new.raw_user_meta_data->>'vehicle',
 case when new.raw_user_meta_data->>'role'='driver' then 'driver' else 'passenger' end);return new;end$$;
create trigger on_signup after insert on auth.users for each row execute function new_user();
create function ride_before() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if exists(select 1 from rides where passenger_id=new.passenger_id and status in('requested','accepted','arrived','started')) then raise exception 'You already have an active ride'; end if;
 new.pname:=(select name from profiles where id=new.passenger_id);
 new.fare:=round(30+12*(12742*asin(sqrt(power(sin(radians(new.dlat-new.plat)/2),2)+cos(radians(new.plat))*cos(radians(new.dlat))*power(sin(radians(new.dlng-new.plng)/2),2)))));
 return new;end$$;
create trigger ride_ins before insert on rides for each row execute function ride_before();

alter table profiles enable row level security;alter table rides enable row level security;
alter table rejections enable row level security;alter table reports enable row level security;
create policy p_sel on profiles for select using(id=auth.uid() or is_admin() or id in(select driver_id from rides where passenger_id=auth.uid()) or id in(select passenger_id from rides where driver_id=auth.uid()));
create policy r_sel on rides for select using(passenger_id=auth.uid() or driver_id=auth.uid() or is_admin() or (status='requested' and is_vdriver()));
create policy r_ins on rides for insert with check(passenger_id=auth.uid() and status='requested' and driver_id is null and exists(select 1 from profiles where id=auth.uid() and active and role='passenger'));
create policy j_sel on rejections for select using(driver_id=auth.uid());
create policy x_ins on reports for insert with check(user_id=auth.uid());
create policy x_sel on reports for select using(user_id=auth.uid() or is_admin());

-- all changes to existing rows go through these checked functions (no direct UPDATE allowed)
create function set_online(o bool,la float8,ln float8) returns void language plpgsql security definer set search_path=public as $$
begin if not is_vdriver() then raise exception 'Driver not verified yet'; end if;update profiles set online=o,lat=la,lng=ln where id=auth.uid();end$$;
create function accept_ride(rid bigint) returns void language plpgsql security definer set search_path=public as $$
begin if not is_vdriver() then raise exception 'Not verified'; end if;
 if exists(select 1 from rides where driver_id=auth.uid() and status in('accepted','arrived','started')) then raise exception 'Finish current ride first'; end if;
 update rides set status='accepted',driver_id=auth.uid() where id=rid and status='requested';  -- row lock: only one driver wins
 if not found then raise exception 'Ride already taken'; end if;end$$;
create function ride_step(rid bigint,s text) returns void language plpgsql security definer set search_path=public as $$
begin update rides set status=s where id=rid and driver_id=auth.uid() and status=case s when 'arrived' then 'accepted' when 'started' then 'arrived' when 'completed' then 'started' end;
 if not found then raise exception 'Wrong ride state'; end if;end$$;
create function reject_ride(rid bigint) returns void language plpgsql security definer set search_path=public as $$
begin if not is_vdriver() then raise exception 'Not allowed'; end if;insert into rejections(ride_id) values(rid) on conflict do nothing;
 update rides set status='requested',driver_id=null where id=rid and driver_id=auth.uid() and status in('accepted','arrived');end$$;
create function cancel_ride(rid bigint) returns void language plpgsql security definer set search_path=public as $$
begin update rides set status='cancelled' where id=rid and passenger_id=auth.uid() and status in('requested','accepted','arrived');
 if not found then raise exception 'Cannot cancel now'; end if;end$$;
create function rate_ride(rid bigint,r int,rv text) returns void language plpgsql security definer set search_path=public as $$
begin update rides set rating=r,review=rv where id=rid and passenger_id=auth.uid() and status='completed' and rating is null;
 if not found then raise exception 'Cannot rate'; end if;end$$;
create function admin_action(uid uuid,act text) returns void language plpgsql security definer set search_path=public as $$
begin if not is_admin() then raise exception 'Admins only'; end if;
 update profiles set verified=verified or act='verify',active=case act when 'suspend' then false when 'restore' then true else active end,online=online and act<>'suspend' where id=uid and role<>'admin';end$$;
alter publication supabase_realtime add table rides;
