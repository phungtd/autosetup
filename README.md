# Tự Động Cài Đặt Website

Script tự động hóa quy trình thiết lập website trên CyberPanel, bao gồm mua tên miền, cấu hình DNS và cài đặt source code.

## Tính Năng Chính

- **Quản Lý Tên Miền**:
  - Tự động kiểm tra và mua tên miền
  - Hỗ trợ Namecheap và Dynadot
  - Tự động cấu hình DNS

- **Quản Lý Source Code**:
  - Tự động tải source từ URL
  - Hỗ trợ các định dạng: zip, tar.gz, tgz, tar, tar.bz2
  - Tự động backup files hiện có
  - Tự động giải nén vào thư mục `public_html`

- **Tích Hợp CyberPanel**:
  - Tự động tạo website
  - Tự động cài SSL
  - Tự động cấu hình PHP
  - Tự động tạo database

## Cài Đặt

### Yêu Cầu
- Linux (Ubuntu/CentOS)
- CyberPanel
- curl hoặc wget
- jq (tự động cài đặt nếu chưa có)

### Các Bước Cài Đặt

1. Clone repo
```bash
git clone https://github.com/phungtd/autosetup.git
cd autosetup
```

2. Copy và sửa file config
```bash
cp config/config.example.ini config/config.ini
nano config/config.ini
```

3. Cấp quyền thực thi
```bash
chmod +x autosetup.sh
```

## Cấu Hình

Chỉnh sửa file `config/config.ini` với các thông tin:

### [defaults]
- `email`: Email mặc định dùng cho đăng ký tên miền và SSL
- `nameserver`: Nhà cung cấp tên miền mặc định (namecheap/dynadot)
- `panel`: Control panel mặc định (cyberpanel)

### [namecheap]
- `api_key`: API key từ Namecheap API Settings
- `api_user`: Tên đăng nhập tài khoản Namecheap
- `api_endpoint`: API endpoint (mặc định: https://api.namecheap.com/xml.response)
- `registrant_fname`: Tên người đăng ký
- `registrant_lname`: Họ người đăng ký
- `registrant_addr1`: Địa chỉ
- `registrant_city`: Thành phố
- `registrant_state`: Tỉnh/Bang
- `registrant_postal`: Mã bưu điện
- `registrant_country`: Mã quốc gia (VN, US,...)
- `registrant_phone`: Số điện thoại (+84.123456789)
- `registrant_email`: Email đăng ký domain, có thể dùng email tài khoản Namecheap

> **Lưu ý**: Các thông tin `registrant_` có thể để trống, script sẽ tự lấy địa chỉ đã lưu từ Namecheap hoặc dùng email ở phần `[defaults]`

### [dynadot]
- `api_key`: API key từ Dynadot API Settings
- `api_endpoint`: API endpoint (mặc định: https://api.dynadot.com/api3.json)

### [sources]
Định nghĩa các nguồn cài đặt. Mỗi nguồn là một cặp key=value:
- `key`: Tên ngắn gọn để gọi source (vd: wp)
- `value`: URL trực tiếp tới file nén (zip/tar.gz)

Ví dụ:
```ini
[sources]
wp = https://wordpress.org/latest.zip
```

## Sử Dụng

### Cơ Bản
```bash
./autosetup.sh
```

### Có Tham Số
```bash
./autosetup.sh --domain example.com --source wp --nameserver namecheap
```

### Các Tham Số
- `--domain`: Tên miền cần cài đặt
- `--source`: Nguồn cài đặt (URL hoặc tên nguồn định nghĩa trong config.ini)
- `--nameserver`: Nhà cung cấp domain (namecheap/dynadot)
- `--panel`: Control panel (cyberpanel)
- `--skip-domain`: Bỏ qua mua domain
- `--skip-dns`: Bỏ qua cấu hình DNS
- `--skip-web`: Bỏ qua tạo website
- `--skip-ssl`: Bỏ qua cài SSL
- `--skip-db`: Bỏ qua tạo database
- `--skip-wp`: Bỏ qua cài WordPress

### Quy Trình Hoạt Động
1. Kiểm tra và mua tên miền
2. Tạo website trong CyberPanel
3. Cài SSL (LetsEncrypt)
4. Tạo database
5. Backup thư mục `public_html` (nếu có)
6. Tải và giải nén source vào `public_html`

## Tạo File Source

### WordPress Duplicator
1. Cài plugin `Duplicator` hoặc `Duplicator Pro`
2. Vào `WP Admin > Duplicator > Backups`
3. Tạo backup (chọn Presets: Full Site nếu dùng Pro)
4. Tải file `Archive` và `Installer`
5. Nén 2 file `...archive.zip` và `...installer.php` vào 1 file zip
6. Upload file zip này lên URL và thêm vào config.ini

## Logs & Debug

Các file log trong thư mục `logs/`:
- Log chi tiết: `logs/autosetup_YYYYMMDD_HHMMSS.log`
- Thông tin đăng nhập: `logs/domain_YYYYMMDD_HHMMSS.txt`

## Bảo Mật

- File cấu hình và logs được tự động set quyền 600
- Mật khẩu database được tự động tạo ngẫu nhiên
- API keys được mã hóa trong logs
- Tự động backup trước khi thay đổi

## TODO
- [ ] Chưa tự động restore
- [ ] ...

## Đóng Góp
Mọi đóng góp đều được chào đón. Vui lòng tạo issue hoặc pull request.

## License
MIT License - xem file [LICENSE](LICENSE) để biết thêm chi tiết. 