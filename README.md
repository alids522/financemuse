# Finance Tracker (financemuse)

Aplikasi pencatatan keuangan pribadi — Flutter Web, Android, iOS — dengan
Supabase sebagai backend. Bahasa id-ID, mata uang IDR, zona waktu
Asia/Jakarta. Implementasi P0 dari PRD v1.0 (2026-11-07).

## P0 yang sudah dibangun

- **Auth**: signup username (3–24 `[a-z0-9_]`) + email + password min 12 (server GOTRUE minimum),
  tanpa konfirmasi email; login username-atau-email (resolusi username→email
  memerlukan layanan server — sampai tersedia, login memakai email);
  suspend check; logout; ubah kata sandi dengan kata sandi lama.
  Tidak ada self-service forgot/reset (v1).
- **Akun**: Cash/Bank/E-wallet/Other, saldo awal, arsip; hapus diblokir bila
  ada transaksi.
- **Transaksi**: expense/income/transfer/adjustment, nominal minor-unit,
  kategori (transfer memakai akun tujuan), effective_at, merchant/deskripsi/
  tag, status draft/pending/posted/voided, split (validasi jumlah = parent),
  duplikat, reversal, soft delete, idempotency_key per create.
  Filter Day/Week/Month/Year/Custom dengan batas bulan kalender
  Asia/Jakarta, pencarian, sort, pagination.
- **Kategori + template**: preset sistem PRD §5.4, kategori custom,
  template quick-add dengan preview sebelum submit.
- **Dashboard**: total saldo, pemasukan/pengeluaran/net, utilisasi budget,
  transaksi terakhir, chart arus kas.
- **Budget vs Actual**: sisa = budget − actual; varians proyeksi =
  budget − forecast EOP; overspend >100% merah/negatif.
- **Forecast**: run_rate / scheduled / hybrid + asumsi + label kepercayaan
  rendah; simulasi skenario tanpa mutasi data. Contoh PRD (budget 5jt,
  actual 2,8jt, 14/30 hari → forecast 6jt, sisa 2,2jt, varians −1jt)
  tercakup unit test.
- **CSV import/export + PDF export**: preview + mapping, fingerprint
  duplikat (akun+tanggal+nominal+deskripsi ternormalisasi), needs_review
  untuk ambiguitas. Impor PDF digital: ekstraksi teks best-effort +
  review wajib; PDF hasil scan menampilkan pesan tidak didukung (OCR = P2).
- **Agents (MCP skeleton)**: matriks izin §6.2, batas approval §6.3
  (auto ≤ Rp1.000.000, approval > Rp1.000.000, edit delta > Rp250.000,
  transfer selalu approval, hapus/bulk selalu approval, admin:* tidak
  pernah via MCP), inbox approval (10 menit), audit log agent.
  `lib/services/mcp_policy.dart` mengimplementasikan `evaluateAction()`.
  Tidak ada server MCP live di pass ini.
- **Admin**: daftar/pencarian user, detail, suspend/reactivate, ubah role
  (lindungi admin terakhir), reset kata sandi berbantuan admin, audit log.
- **Pengaturan**: profil, tema gelap/terang/sistem, IDR, Asia/Jakarta,
  awal minggu.
- **Tabungan / Utang / Berulang**: CRUD dasar. Otomasi (jadwal, cicilan,
  proyeksi) adalah TODO P1.
- **Navigasi**: sidebar kiri collapsible (240px → rail 64px) ≥1200px,
  drawer <768px (tutup otomatis saat navigasi), tanpa bottom tabs.
- **Desain**: token PRD §8.2, Inter (fallback sistem bila bundling gagal),
  radius 8, spacing 4/8/12/16/24/32.

## Setup

```sh
flutter pub get
flutter run --dart-define SUPABASE_URL=https://supabase.adoetz52.my.id \
  --dart-define SUPABASE_ANON_KEY=<anon-key>
```

Kunci anon TIDAK disimpan di repo, tidak dicetak, dan tidak di-commit.
Ambil dari `/root/supabase-project/.env` di server oracle hanya lewat
substitusi perintah saat build (lihat perintah build di bawah). Bila kunci
kosong, aplikasi tetap jalan dan menampilkan pemberitahuan konfigurasi.

Build web rilis:

```sh
flutter build web --release \
  --dart-define SUPABASE_URL=https://supabase.adoetz52.my.id \
  --dart-define=SUPABASE_ANON_KEY=$(sudo grep -m1 ANON_KEY /root/supabase-project/.env | cut -d= -f2-)
```

Periksa dulu nama kunci sebenarnya di file tersebut (hanya nama kunci,
jangan pernah menampilkan nilainya).

## PostgREST: skema financemuse SUDAH diekspos (2026-11-07)

Seluruh data layer (`lib/services/finance_service.dart`) memanggil Supabase
client pada skema `financemuse` (`.schema('financemuse').from(...)`) sesuai
tabel PRD §10. Skema ini sudah diekspos via PostgREST:

- Dulu: `PGRST_DB_SCHEMAS=public,storage,graphql_public,waclonegem`
- Kini: `PGRST_DB_SCHEMAS=public,storage,graphql_public,waclonegem,financemuse`
  (backup `.env` lama: `/root/supabase-project/backups/.env.bak-20261107-financemuse`;
  container `supabase-rest` dibuat ulang, cache PostgREST 84 relasi)
- `private` tetap TIDAK diekspos.
- Grants: `anon` hanya USAGE pada skema (tanpa grant tabel apa pun —
  panggilan anon ke tabel mengembalikan 401/42501); `authenticated` punya
  SELECT/INSERT/UPDATE/DELETE pada 35 objek financemuse.
- RLS aktif di semua 34 tabel, kebijakan owner-only (`auth.uid() =
  user_id`); kategori sistem (`user_id` NULL) bisa dibaca semua user
  yang login; tabel anak (splits, tags, dsb.) lewat kebijakan parent.
- OAuth direct Data API tetap TERTUTUP sesuai PRD §6.5 — akses data hanya
  lewat client Supabase dengan JWT user (atau service-role di backend).

Aplikasi menangani kegagalan API dengan jujur: setiap layar menampilkan
pemberitahuan beserta detail teknis — **tidak ada data contoh dan tidak
ada fallback mock diam-diam**.

### Batasan yang masih berlaku

1. **Pendaftaran user baru DIBLOKIR** oleh trigger instance-wide
   `private.on_signup` pada `auth.users` (500 P0001 "Registration is
   invitation only") — berlaku untuk semua signup, termasuk pembuatan
   lewat Auth Admin API. Trigger ini TIDAK diubah/dinonaktifkan oleh
   proyek ini dan skema adoetz (`private`/`public`) tidak disentuh.
   User financemuse baru belum bisa mendaftar sampai Adoetz memutuskan
   soal trigger tersebut. Login username di bawah ini hanya membantu
   user yang SUDAH ada.
2. **Login username-only** kini bekerja untuk user yang sudah ada, lewat
   Edge Function `financemuse-login` (`POST /functions/v1/financemuse-login`
   dengan `{identifier, password}`) + RPC `financemuse.resolve_login_email`
   (SECURITY DEFINER, hanya `service_role` yang boleh mengeksekusi;
   migrasi `supabase/migrations/20261107220000_financemuse_login_rpc.sql`).
   Fungsi ini tidak pernah mengembalikan email ke client dan selalu
   membalas 401 generik yang identik untuk username tak dikenal, akun
   suspended, maupun kata sandi salah. Aplikasi memanggilnya dari
   `AuthService.signIn` lalu memasang sesi lewat `auth.setSession`.
   Verifikasi end-to-end jalur sukses (kata sandi benar) masih menunggu
   kata sandi akun uji / pengujian oleh Adoetz — jalur gagal sudah
   terverifikasi identik dan bebas bocor email.

Saldo otoritatif berasal dari journal ledger (PRD §9.3). Sampai view/fungsi
saldo tersedia, dashboard menghitung saldo dari saldo awal + transaksi
posted dan melabelinya demikian di UI.

## First-admin bootstrap

Admin pertama dibuat lewat `scripts/bootstrap_admin.sh` di server
(bukan akun pertama otomatis, bukan endpoint publik) — script tersebut
ditambahkan terpisah oleh parent. Role dibaca dari
`financemuse.user_roles` (server-owned); UI menyembunyikan menu admin
untuk non-admin, tetapi otorisasi tetap ditegakkan server-side.

Mutasi admin (suspend, ubah role, reset kata sandi) memerlukan backend
service-role / Edge Function — client anon tidak dapat melakukannya.
UI + service call sudah ada dan menampilkan error server secara jujur
sampai backend itu tersedia. **Jangan pernah menanam service-role key
di aplikasi.**

## Struktur

```
lib/
  main.dart            entrypoint + Supabase init
  router.dart          go_router (semua route PRD §4.3)
  theme/app_theme.dart token PRD §8.2
  utils/               money_period.dart, forecast.dart
  services/            supabase_client.dart, auth_service.dart,
                       finance_service.dart, mcp_policy.dart,
                       csv_service.dart, pdf_export.dart, save_bytes*.dart
  state/app_state.dart session, role, tema, periode
  widgets/             app_shell.dart (sidebar/drawer), common.dart
  screens/             auth, dashboard, transactions, accounts,
                       categories/templates, budgets/forecast/analytics,
                       savings/debts/recurring, data, agents,
                       settings, admin
docs/openapi.yaml      REST /api/v1 outline (PRD §11)
test/                  unit test: money, periode, budget/forecast,
                       idempotency, MCP policy, CSV
```

## Identitas aplikasi

- applicationId / iOS bundle id: `com.adoetzfinance.muse`
- Nama tampil: Finance Tracker
- Android namespace: `com.adoetzfinance.muse`

## TODO (P1/P2, bukan fitur P0)

- Offline queue matang (P1), sinkronisasi konflik `row_version`.
- Otomasi recurring, jadwal cicilan utang, proyeksi tabungan (P1).
- Akurasi forecast historis, confidence band (P1).
- OCR PDF hasil scan (P2), kategorisasi AI (P2), household (P2),
  investasi/net worth (P2).
- Server MCP live + OAuth consent + Edge Function admin (service-role).
- Username→email lookup server-side untuk login dengan username.
- View/fungsi saldo berbasis journal ledger di database.

## CI — APK build (GitHub Actions)

Workflow `.github/workflows/build-apk.yml` runs on push to `main` and on
manual dispatch: sets up Flutter stable, runs `flutter analyze`, builds a
release APK, and uploads `app-release.apk` as an artifact (30-day retention).

Required repo secret (Settings > Secrets and variables > Actions):
`SUPABASE_ANON_KEY` — the Supabase publishable/anon key for
https://supabase.adoetz52.my.id. Never commit the key itself. If the secret
is not set, the build still succeeds; the app shows a configuration notice
at runtime instead of crashing.
