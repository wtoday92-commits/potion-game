# Что докрутить на стороне Supabase

Клиент (`scripts/potion_auth.gd`) теперь читает свою строку в топе перед записью
и обновляет её только при новом рекорде. Но полностью дубли закрываются на
сервере: без ограничения в БД одновременный запуск с двух устройств всё ещё
может вставить две строки.

Запускать в SQL Editor проекта по порядку.

## 1. Свести уже накопившиеся дубли к лучшему счёту

```sql
delete from public.leaderboard a
using public.leaderboard b
where a.user_id = b.user_id
  and a.board   = b.board
  and (a.score < b.score or (a.score = b.score and a.ctid > b.ctid));
```

## 2. Одна строка на игрока и доску — навсегда

```sql
create unique index if not exists leaderboard_user_board_uniq
  on public.leaderboard (user_id, board);
```

## 3. Политики RLS на свою строку

Обновление нужно, чтобы клиент переписывал рекорд, а не удалял и вставлял
заново (удаление без политики отвечает 204 и молча не удаляет ничего — из-за
этого игрок и попадал в топ повторно).

```sql
create policy "leaderboard update own"
  on public.leaderboard for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "leaderboard delete own"
  on public.leaderboard for delete
  using (auth.uid() = user_id);
```

## 4. Колонка user_id должна читаться

Клиент просит `select=name,score,created_at,user_id`, чтобы точно подсветить
свою строку и развести одинаковые ники. Если грант на колонку закрыт, запрос
падает и клиент откатывается на старый набор полей — подсветка тогда работает
по нику. Проверить:

```sql
grant select (name, score, created_at, user_id) on public.leaderboard to anon, authenticated;
```

## Ники-двойники

Уникальность ника НЕ навязывается: `profiles.nickname` свободный, два аккаунта
могут назваться одинаково. В топе такие строки клиент подписывает коротким
хвостом id (`Мага#7f3a`), своя строка помечается «· ты». Если захочется жёсткой
уникальности:

```sql
create unique index if not exists profiles_nickname_uniq
  on public.profiles (lower(nickname));
```

Тогда `push_profile` начнёт возвращать 409 на занятом нике, и в UI смены ника
понадобится показ ошибки — сейчас его нет.
