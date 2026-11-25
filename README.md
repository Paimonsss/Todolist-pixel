# Tugas Quest

Todolist bertema pixel yang mengambil tugas dari kalender BRONE UB dan mengirim push notification ke HP.

## Menjalankan di komputer

```powershell
npm install
npm start
```

Buka http://localhost:3000, buat password aplikasi, lalu buka Pengaturan untuk menempel link kalender BRONE.

## Agar notifikasi sampai ke HP

Aplikasi harus berjalan terus di server dengan alamat HTTPS. Atur environment berikut:

| Nama | Isi |
| --- | --- |
| `NODE_ENV` | `production` |
| `APP_PASSWORD` | Password aplikasi, minimal 8 karakter. Jangan pakai password UB. |
| `APP_URL` | Alamat HTTPS aplikasi |
| `DATA_DIR` | Folder penyimpanan permanen |

Perintah build `npm install`, perintah start `npm start`. Layanan yang tidur saat idle tidak cocok karena pengingat bisa terlambat.

Di Android, buka lewat Chrome lalu pasang ke layar utama. Di iPhone (iOS 16.4+), buka lewat Safari, pilih Add to Home Screen, lalu aktifkan notifikasi dari ikon aplikasi.

## Keamanan

Link kalender BRONE bersifat rahasia. Link itu tersimpan di `DATA_DIR/state.json`, jadi jangan bagikan atau commit folder tersebut.
