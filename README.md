# VPS Tunnel: Headscale + Nginx Proxy Manager

Boilerplate triển khai **Headscale** (control server cho Tailscale client) phía sau **Nginx Proxy Manager (NPM)** để có HTTPS/SSL dễ quản lý.

## Thành phần

- `headscale`: chạy control plane trên cổng nội bộ `8080`
- `nginx-proxy-manager`: reverse proxy + SSL, mở cổng `80`, `81`, `443`
- `headscale-ui`: giao diện web quản lý users/nodes/routes của Headscale
- `connect-tailscale.sh`: script chạy ở máy client để cài và join về Headscale
- `create-headscale-user-key.sh`: script chạy ở VPS để tạo user + auth key và in ra 1 dòng lệnh connect

## Cấu trúc thư mục

```text
.
├── docker-compose.yml
├── .env.example
├── .gitignore
├── connect-tailscale.sh
├── create-headscale-user-key.sh
└── headscale/
    └── config.yaml
```

## 1) Chuẩn bị domain

Trỏ DNS record (A/AAAA) của domain về IP VPS, ví dụ:

- `headscale.example.com` -> `IP_VPS`

Tạo file `.env` từ `.env.example` và sửa:

- `HEADSCALE_URL=https://headscale.example.com`
- `HEADSCALE_PREFIX_V4=10.10.0.0/16`

`headscale/config.yaml` đang là template và sẽ tự nhận URL từ biến `HEADSCALE_URL` và IPv4 prefix từ `HEADSCALE_PREFIX_V4` khi container start.

## 2) Khởi động dịch vụ

Dùng `docker-compose`:

```bash
docker-compose up -d
```

## 3) Cấu hình Nginx Proxy Manager

Mở giao diện admin:

- `http://IP_VPS:81`

Tạo Proxy Host:

1. Domain Names: `headscale.example.com`
2. Scheme: `http`
3. Forward Hostname/IP: `headscale`
4. Forward Port: `8080`
5. Bật `Websockets Support`
6. Tab SSL: Request a new SSL Certificate, bật `Force SSL`

Thêm Custom Location để mở UI trên cùng domain (tránh lỗi CORS):

1. Location: `/web`
2. Scheme: `http`
3. Forward Hostname/IP: `headscale-ui`
4. Forward Port: `8080`

Sau đó truy cập UI tại `https://headscale.example.com/web`.

Trong UI, vào Settings và nhập:

1. API URL: `https://headscale.example.com`
2. API Key: tạo trên server bằng lệnh:

```bash
docker-compose exec headscale headscale apikeys create
```

Neu ban dung Nginx thuong thay vi NPM, da co mau cau hinh SSL reverse proxy tai:

- `nginx/headscale-ssl.conf.example`
- `nginx/npm-admin-ssl.conf.example`

Mau nay da gom:

- Redirect HTTP -> HTTPS
- Forward `/` ve Headscale
- Forward `/web` ve Headscale UI tren cung domain
- Forward NPM Admin UI qua domain rieng (proxy vao port 81)

## 4) Tạo user + auth key tự động

Chạy trên VPS:

```bash
./create-headscale-user-key.sh https://headscale.example.com main 24h
```

Script sẽ lưu key mới tạo vào file `key.txt` ở thư mục gốc project (file này đã được git ignore).

Kết quả sẽ in ra **1 dòng lệnh duy nhất** dạng:

```bash
sudo ./connect-tailscale.sh "https://headscale.example.com" "tskey-xxxxx" <client-hostname>
```

Bạn copy dòng này sang máy client để chạy.

## 5) Connect client vào Headscale

Trên máy client Linux:

```bash
sudo ./connect-tailscale.sh https://headscale.example.com tskey-client-xxxxx my-laptop
```

Script sẽ:

- tự cài `tailscale` nếu chưa có
- bật `tailscaled`
- chạy `tailscale up --login-server ... --authkey ...`

## 6) Kiểm tra node đã join

Trên VPS:

```bash
docker-compose exec headscale headscale nodes list
```

## Biến môi trường mẫu

File `.env.example` hiện có:

```env
HEADSCALE_URL=https://headscale.example.com
HEADSCALE_PREFIX_V4=10.10.0.0/16
HEADSCALE_USER=main
HEADSCALE_KEY_EXPIRATION=24h
```

Bạn có thể copy thành `.env` để lưu thông tin local, file này đã được ignore trong git.

## Lưu ý bảo mật

- Không commit auth key vào git/chat/public logs
- Ưu tiên auth key có `expiration` ngắn
- Nên giới hạn firewall chỉ mở `80/443/81` theo nhu cầu quản trị

## Troubleshooting nhanh

- Kiểm tra container:

```bash
docker-compose ps
```

- Xem log headscale:

```bash
docker-compose logs -f headscale
```
