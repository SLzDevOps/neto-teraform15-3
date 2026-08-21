# storage.tf

# 1. Используем существующий сервисный аккаунт terraform-acc
data "yandex_iam_service_account" "sa_storage" {
  name = "terraform-acc"
}

# 2. Создаем статический ключ для существующего аккаунта
resource "yandex_iam_service_account_static_access_key" "sa_storage_key" {
  service_account_id = data.yandex_iam_service_account.sa_storage.id
}

# 3. Создание симметричного KMS ключа
resource "yandex_kms_symmetric_key" "bucket_encryption_key" {
  name              = "bucket-encryption-key"
  description       = "Key for encrypting Object Storage bucket"
  default_algorithm = "AES_128"
  rotation_period   = "8760h"
}

# 4. Создание бакета Object Storage с шифрованием
resource "yandex_storage_bucket" "images" {
  bucket     = var.bucket_name
  access_key = yandex_iam_service_account_static_access_key.sa_storage_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa_storage_key.secret_key

  # Шифрование через KMS
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = yandex_kms_symmetric_key.bucket_encryption_key.id
        sse_algorithm     = "aws:kms"
      }
    }
  }

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

# 5. Делаем бакет публичным через grant
resource "yandex_storage_bucket_grant" "public_read" {
  bucket = yandex_storage_bucket.images.bucket

  grant {
    permissions = ["READ"]
    type        = "Group"
    uri         = "http://acs.amazonaws.com/groups/global/AllUsers"
  }
}

# 6. Загрузка картинки в бакет
resource "yandex_storage_object" "image" {
  access_key = yandex_iam_service_account_static_access_key.sa_storage_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa_storage_key.secret_key
  bucket     = yandex_storage_bucket.images.bucket
  key        = "example-image.jpg"
  source     = var.image_path

  depends_on = [
    yandex_storage_bucket.images,
    yandex_storage_bucket_grant.public_read
  ]
}

# 7. Получение URL картинки
output "image_url" {
  value = "https://storage.yandexcloud.net/${yandex_storage_bucket.images.bucket}/${yandex_storage_object.image.key}"
}
