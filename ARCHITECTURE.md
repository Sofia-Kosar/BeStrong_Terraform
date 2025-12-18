# 🏗️ Архітектура проєкту BeStrong - Infrastructure as Code

## 📑 Зміст
1. [Огляд файлів](#огляд-файлів)
2. [Як покриваються вимоги](#як-покриваються-вимоги)
3. [Схема інфраструктури](#схема-інфраструктури)

---

## 📂 Огляд файлів

### 🔧 **Конфігураційні файли (основа)**

#### `versions.tf` - Версії та провайдери
**Призначення:** Визначає версії Terraform та Azure провайдера
- Фіксує версію Terraform (>= 1.0)
- Вказує версію Azure RM провайдера
- Гарантує сумісність і відтворюваність інфраструктури

#### `providers.tf` - Налаштування Azure
**Призначення:** Конфігурує підключення до Azure
```hcl
provider "azurerm" {
  subscription_id = var.subscription_id  # Ваша підписка Azure
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false  # Для dev середовища
    }
  }
}
```
**Чому саме так:**
- `subscription_id` — явно вказує, в яку підписку розгортати
- `features` — включає безпечне видалення ресурсів

#### `variables.tf` - Змінні проєкту
**Призначення:** Оголошує всі параметри, які можна змінювати
```hcl
variable "subscription_id"      # ID Azure підписки
variable "location"             # Регіон (northeurope)
variable "project"              # Назва проєкту (bestrong)
variable "env"                  # Середовище (dev/prod)
variable "sql_admin_login"      # Логін SQL (секрет)
variable "sql_admin_password"   # Пароль SQL (секрет)
variable "app_image"            # Docker образ
variable "enable_app_service"   # Увімкнути App Service
variable "tags"                 # Додаткові теги
```

#### `terraform.tfvars` - Фактичні значення
**Призначення:** Конкретні значення змінних для вашого середовища
- В `.gitignore` — НЕ потрапляє в Git (захист секретів)
- Містить реальні паролі, ID підписки
- Можна мати різні файли для dev/prod

#### `backend.tf` - ⚠️ **ДУЖЕ ВАЖЛИВО!**
**Призначення:** Зберігання стану Terraform в Azure Storage
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-bestrong-tfstate"
    storage_account_name = "stbestrongtfstate001"
    container_name       = "tfstate"
    key                  = "bestrong-infra.tfstate"
  }
}
```
**Покриває вимогу #8:**
- ✅ Стан НЕ на ноутбуці — в Azure Storage
- ✅ Безпека — файл `.tfstate` в хмарі, не губиться
- ✅ Командна робота — всі бачать одну версію стану
- ✅ Блокування — якщо хтось працює, інші чекають

---

### 🎯 **Основні файли інфраструктури**

#### `main.tf` - Фундамент
**Призначення:** Resource Group та загальні налаштування
```hcl
locals {
  name = "bestrong-dev"              # Комбінація project-env
  tags = {                           # Теги для всіх ресурсів
    project = "bestrong"
    env = "dev"
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-bestrong-dev"
  location = "northeurope"
}
```
**Чому Resource Group:**
- Логічний контейнер для всіх ресурсів
- Одна команда `terraform destroy` — видалить все
- Billing — бачите витрати по проєкту
- RBAC — права доступу на весь проєкт

---

#### `network.tf` - Приватна мережа
**Призначення:** Ізольована мережа (VNet) для всіх сервісів

**Покриває вимогу #5: "Наша приватна територія"**

```hcl
# Віртуальна мережа (10.10.0.0/16)
azurerm_virtual_network "vnet"
  ├─ address_space = ["10.10.0.0/16"]  # 65,536 IP адрес
  
# Subnet для App Service (10.10.1.0/24)
azurerm_subnet "snet_app"
  ├─ address_prefixes = ["10.10.1.0/24"]  # 256 адрес
  └─ delegation = "Microsoft.Web/serverFarms"  # Тільки для App Service

# Subnet для Private Endpoints (10.10.2.0/24)
azurerm_subnet "snet_pe"
  └─ address_prefixes = ["10.10.2.0/24"]  # 256 адрес
```

**Чому дві підмережі:**
1. **snet-app** — делегована App Service:
   - App Service підключається сюди (VNet Integration)
   - Дозволяє додатку ходити в приватну мережу
   - Delegation потрібна для Azure App Service

2. **snet-private-endpoints** — для Private Endpoints:
   - Тут живуть приватні IP всіх сервісів
   - SQL Server буде 10.10.2.5
   - Key Vault буде 10.10.2.6
   - ACR буде 10.10.2.7 тощо

**Що це дає:**
- ✅ Ізоляція — ніхто ззовні не доступається
- ✅ Безпека — весь трафік всередині Azure
- ✅ Контроль — можна додати Firewall, NSG rules

---

#### `appservice.tf` - Де живе код
**Призначення:** Managed платформа для запуску вашого додатку

**Покриває вимогу #1: "Where our code will live"**

```hcl
# Service Plan (тарифний план)
azurerm_service_plan "plan"
  ├─ os_type = "Linux"
  └─ sku_name = "B1"  # Basic - $13/місяць

# Linux Web App (сам додаток)
azurerm_linux_web_app "app"
  ├─ identity { type = "SystemAssigned" }  # 🔑 Managed Identity
  ├─ site_config {
  │   └─ docker_image_name = "nginx:latest"  # Ваш Docker образ
  │ }
  ├─ app_settings {  # Змінні середовища
  │   ├─ APPLICATIONINSIGHTS_CONNECTION_STRING
  │   ├─ SQLSERVER_FQDN
  │   └─ SQLDB_NAME
  │ }
  └─ storage_account {  # Монтує Azure Files як папку
      ├─ mount_path = "/mounts/uploads"
      └─ share_name = "uploads"
    }

# VNet Integration (вихідний трафік через VNet)
azurerm_app_service_virtual_network_swift_connection
  └─ subnet_id = snet_app

# Private Endpoint (вхідний трафік через VNet)
azurerm_private_endpoint "pe_web"
  └─ subnet_id = snet_pe
```

**Чому App Service, а не VM:**
- ✅ **Managed** — Azure займається:
  - Оновленнями ОС
  - Патчами безпеки
  - Масштабуванням
  - Load balancing
  - SSL сертифікатами

- ✅ **SystemAssigned Identity** (Managed Identity):
  ```
  Без Identity:               З Identity:
  app → password → ACR       app [is] identity → ACR
  app → password → KeyVault  app [introduce] itself → KeyVault
  app → password → SQL       app [shows badge] → SQL
  ```
  - Додаток "представляється" без паролів
  - Azure сама керує ротацією токенів
  - Неможливо вкрасти пароль (його немає!)

- ✅ **VNet Integration**:
  - Вихідний трафік → через приватну мережу
  - Додаток бачить SQL по 10.10.2.5, а не через інтернет

- ✅ **Private Endpoint**:
  - Вхідний трафік → тільки з VNet
  - Не exposed в інтернет (якщо налаштувати)

- ✅ **Storage Mount**:
  - Azure Files монтується як `/mounts/uploads`
  - Код працює з файлами як з локальною папкою
  - `fs.writeFile('/mounts/uploads/photo.jpg')`

**Чому count = var.enable_app_service:**
- Можна вимкнути (економія грошей)
- У вас зараз вимкнено через квоту

---

#### `monitoring.tf` - Спостереження
**Призначення:** Логи, метрики, помилки

**Покриває вимогу #2: "See what's happening"**

```hcl
# Log Analytics Workspace (центральне сховище логів)
azurerm_log_analytics_workspace "law"
  └─ retention_in_days = 30  # Зберігаємо 30 днів

# Application Insights (моніторинг додатку)
azurerm_application_insights "appi"
  ├─ application_type = "web"
  └─ workspace_id = law.id  # Зв'язок з LAW
```

**Що це дає:**

1. **Application Insights** автоматично збирає:
   - 📊 **Performance**: час відповіді API
   - 🔴 **Errors**: всі exceptions
   - 📈 **Dependencies**: скільки разів ходили в SQL
   - 🔍 **Traces**: ваші console.log()
   - 👤 **Users**: скільки користувачів онлайн

2. **Приклад використання в коді:**
   ```javascript
   const appInsights = require('applicationinsights');
   appInsights.setup(process.env.APPLICATIONINSIGHTS_CONNECTION_STRING);
   appInsights.start();
   
   // Автоматично логується:
   app.get('/api/users', async (req, res) => {
     const users = await db.query('SELECT * FROM users');
     res.json(users);
   });
   ```

3. **В Azure Portal:**
   ```
   Application Insights → Failures
   ├─ Server exceptions (500 errors)
   ├─ Failed dependencies (SQL timeouts)
   └─ Stack traces (де впав код)
   
   Application Insights → Performance
   ├─ Slow API endpoints
   └─ SQL queries performance
   
   Log Analytics → Logs (KQL query)
   traces | where message contains "error"
   ```

**Чому connection string в app_settings:**
- Додаток автоматично підключається
- Всі бібліотеки розуміють це середовище

---

#### `acr.tf` - Склад для Docker образів
**Призначення:** Приватний Docker Registry

**Покриває вимогу #3: "Where to put our containers"**

```hcl
# Azure Container Registry
azurerm_container_registry "acr"
  ├─ name = "acrbestrongdev001"
  ├─ sku = "Premium"  # Потрібно для Private Endpoint
  └─ admin_enabled = false  # ⛔ Без паролів!

# Private Endpoint для ACR
azurerm_private_endpoint "pe_acr"
  ├─ subnet_id = snet_pe
  └─ subresource_names = ["registry"]
```

**Workflow:**
```bash
# 1. Build образу локально
docker build -t myapp:1.0.0 .

# 2. Login в ACR (без пароля, через Azure AD)
az acr login --name acrbestrongdev001

# 3. Tag та push
docker tag myapp:1.0.0 acrbestrongdev001.azurecr.io/backend:1.0.0
docker push acrbestrongdev001.azurecr.io/backend:1.0.0

# 4. App Service pull (через Managed Identity)
# App Service автоматично витягує образ
```

**Чому Premium SKU:**
- Private Endpoint — публічного доступу немає
- Geo-replication — можна реплікувати в інші регіони
- Image scanning — перевірка вразливостей

**Чому admin_enabled = false:**
- Не використовуємо username/password
- Тільки через Azure AD або Managed Identity
- App Service підключається через свою Identity (rbac.tf)

---

#### `rbac.tf` - Права доступу
**Призначення:** Дозволи для Managed Identity

```hcl
# Дозвіл витягувати образи з ACR
azurerm_role_assignment "acr_pull"
  ├─ scope = acr.id
  ├─ role_definition_name = "AcrPull"
  └─ principal_id = app.identity.principal_id
  # Перекладено: App Service може робити docker pull

# Дозвіл читати секрети з Key Vault
azurerm_role_assignment "kv_secrets_user"
  ├─ scope = key_vault.id
  ├─ role_definition_name = "Key Vault Secrets User"
  └─ principal_id = app.identity.principal_id
  # Перекладено: App Service може читати секрети
```

**Що це дає:**
```
БЕЗ RBAC:                      З RBAC:
App → ❌ ACR Access Denied    App → ✅ ACR Pull Success
App → ❌ KV 403 Forbidden     App → ✅ KV Secret Retrieved
```

**Чому count:**
- Якщо App Service вимкнено → RBAC не потрібен
- Немає principal_id без App Service

---

#### `keyvault.tf` - Сейф для секретів
**Призначення:** Зберігання паролів, API ключів, токенів

**Покриває вимогу #4: "Safe for passwords"**

```hcl
# Key Vault
azurerm_key_vault "kv"
  ├─ name = "kv-bestrong-dev-o91q"  # Унікальна назва (suffix)
  ├─ sku_name = "standard"
  ├─ public_network_access_enabled = false  # ⛔ Немає публічного доступу
  ├─ purge_protection_enabled = true  # Не можна випадково видалити
  └─ soft_delete_retention_days = 7  # Відновлення протягом 7 днів

# Private Endpoint
azurerm_private_endpoint "pe_kv"
  ├─ subnet_id = snet_pe
  └─ subresource_names = ["vault"]
```

**Використання в коді:**
```javascript
const { DefaultAzureCredential } = require('@azure/identity');
const { SecretClient } = require('@azure/keyvault-secrets');

// Автентифікація через Managed Identity
const credential = new DefaultAzureCredential();
const vaultUrl = "https://kv-bestrong-dev-o91q.vault.azure.net";
const client = new SecretClient(vaultUrl, credential);

// Отримати секрет
const secret = await client.getSecret("SendGridApiKey");
console.log(secret.value);  // Ніколи не хардкодити!
```

**Що зберігати в Key Vault:**
- ✅ API ключі (SendGrid, Stripe)
- ✅ Connection strings (якщо не в app_settings)
- ✅ Сертифікати SSL
- ✅ Токени OAuth
- ❌ Не зберігати конфіги (це не для цього)

**Чому purge_protection:**
- Навіть якщо видалите — 7 днів на відновлення
- Захист від випадкового `terraform destroy`

**Чому public_network_access_enabled = false:**
- Доступ ТІЛЬКИ з VNet
- Неможливо підключитися через інтернет

---

#### `sql.tf` - База даних
**Призначення:** SQL Server для структурованих даних

**Покриває вимогу #6: "Where to store data"**

```hcl
# SQL Server
azurerm_mssql_server "sql"
  ├─ name = "sql-bestrong-dev-001"
  ├─ version = "12.0"  # SQL Server 2019
  ├─ administrator_login = var.sql_admin_login
  ├─ administrator_login_password = var.sql_admin_password
  └─ public_network_access_enabled = false  # ⛔ Приватний

# SQL Database
azurerm_mssql_database "db"
  ├─ name = "bestrongdb"
  ├─ server_id = sql.id
  └─ sku_name = "S0"  # Standard tier (~$15/місяць)

# Private Endpoint
azurerm_private_endpoint "pe_sql"
  ├─ subnet_id = snet_pe
  └─ subresource_names = ["sqlServer"]
```

**Connection String (в app_settings):**
```javascript
const sql = require('mssql');

const config = {
  server: process.env.SQLSERVER_FQDN,  // sql-bestrong-dev-001.database.windows.net
  database: process.env.SQLDB_NAME,    // bestrongdb
  authentication: {
    type: 'azure-active-directory-msi-app-service'  // Managed Identity!
  },
  options: {
    encrypt: true
  }
};

await sql.connect(config);
const result = await sql.query`SELECT * FROM users`;
```

**Чому SQL Server, а не PostgreSQL:**
- Ваші девелопери знають SQL Server ✅
- Entity Framework / Dapper працює добре
- SQL Management Studio для адмінів

**Чому Private Endpoint:**
- З App Service: `app → VNet → Private IP (10.10.2.x) → SQL`
- З інтернету: `hacker → ❌ No route`

**Як підключитися адміну:**
```bash
# Треба або:
1. VPN до VNet
2. Azure Bastion
3. Тимчасово включити public access (НЕ рекомендовано)
4. Azure Data Studio через Azure Portal
```

---

#### `storage_files.tf` - Файли користувачів
**Призначення:** Azure Files для зберігання документів/фото

**Покриває вимогу #7: "For user files"**

```hcl
# Storage Account
azurerm_storage_account "st"
  ├─ name = "stbestrongdev001"
  ├─ account_tier = "Standard"
  ├─ account_replication_type = "LRS"  # Locally Redundant
  └─ public_network_access_enabled = false  # ⛔ Приватний

# File Share (SMB/NFS share)
azurerm_storage_share "files"
  ├─ name = "uploads"
  └─ quota = 100  # 100 GB

# Private Endpoint
azurerm_private_endpoint "pe_file"
  ├─ subnet_id = snet_pe
  └─ subresource_names = ["file"]
```

**Як це працює в App Service:**
```hcl
# В appservice.tf:
storage_account {
  name       = "uploads"
  mount_path = "/mounts/uploads"
  share_name = "uploads"
  access_key = storage_account.primary_access_key
}
```

**В коді додатку:**
```javascript
const fs = require('fs').promises;
const path = require('path');

// Збереження файлу
app.post('/upload', upload.single('file'), async (req, res) => {
  const filePath = path.join('/mounts/uploads', req.file.originalname);
  await fs.writeFile(filePath, req.file.buffer);
  res.json({ path: filePath });
});

// Читання файлу
app.get('/files/:name', async (req, res) => {
  const filePath = path.join('/mounts/uploads', req.params.name);
  res.sendFile(filePath);
});
```

**Чому Azure Files:**
- ✅ Монтується як папка — простий код
- ✅ Не треба SDK/API — просто `fs.writeFile()`
- ✅ Shared storage — якщо 2+ інстанси App Service → бачать ті ж файли
- ✅ Backup — можна налаштувати автобекапи

**Альтернативи:**
- ❌ Blob Storage — потрібен SDK, складніше
- ✅ Але Blob дешевший для великих об'ємів (терабайти)

---

#### `dns.tf` - Приватні DNS зони
**Призначення:** Резолвінг приватних IP адрес

```hcl
# 5 приватних DNS зон
local.private_dns_zones = {
  vault = "privatelink.vaultcore.azure.net"     # Key Vault
  web   = "privatelink.azurewebsites.net"       # App Service
  sql   = "privatelink.database.windows.net"    # SQL Server
  file  = "privatelink.file.core.windows.net"   # Storage Files
  acr   = "privatelink.azurecr.io"              # ACR
}

# Для кожної зони:
azurerm_private_dns_zone
azurerm_private_dns_zone_virtual_network_link  # Прив'язка до VNet
```

**Навіщо це потрібно:**
```
БЕЗ Private DNS:
app → sql-bestrong-dev-001.database.windows.net
    → DNS повертає публічний IP (20.50.100.10)
    → ❌ Connection blocked (public access disabled)

З Private DNS:
app → sql-bestrong-dev-001.database.windows.net
    → Private DNS повертає приватний IP (10.10.2.5)
    → ✅ Connection через VNet
```

**Як це працює:**
1. Private Endpoint створює IP `10.10.2.5` в `snet_pe`
2. Private DNS Zone створює запис: `sql-xxx.database.windows.net → 10.10.2.5`
3. VNet Link дозволяє VNet користуватися цією DNS зоною
4. App Service резолвить ім'я → отримує приватний IP → підключається

---

#### `random.tf` - Унікальні суфікси
**Призначення:** Генерація унікальних назв

```hcl
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}
# Результат: o91q
```

**Навіщо:**
- Key Vault: `kv-bestrong-dev-o91q` (глобально унікальне ім'я)
- Якщо щось зламається — нова назва
- Уникнення конфліктів з іншими проєктами

---

#### `outputs.tf` - Вихідні дані
**Призначення:** Показує важливу інформацію після розгортання

```hcl
output "acr_login_server" {
  value = "acrbestrongdev001.azurecr.io"
}
output "sql_server_fqdn" {
  value = "sql-bestrong-dev-001.database.windows.net"
}
```

**Використання:**
```bash
terraform output
# acr_login_server = "acrbestrongdev001.azurecr.io"

terraform output -raw acr_login_server
# acrbestrongdev001.azurecr.io

# В CI/CD:
ACR_NAME=$(terraform output -raw acr_login_server)
docker push $ACR_NAME/backend:1.0.0
```

---

## 🎯 Як покриваються вимоги

### 1️⃣ **Where our code will live**
**Файли:** `appservice.tf`, `rbac.tf`

✅ **Managed платформа** — App Service
  - Не треба керувати VM, оновленнями, патчами
  - Azure все робить за вас

✅ **Managed Identity** — представлення без паролів
  ```
  App Service → "Я це app-bestrong-dev" → ACR дає образ
  App Service → "Я це app-bestrong-dev" → Key Vault дає секрети
  App Service → "Я це app-bestrong-dev" → SQL дає доступ
  ```

✅ **Приватна мережа**
  - VNet Integration — вихідний трафік через VNet
  - Private Endpoint — вхідний трафік тільки з VNet
  - Не exposed в інтернет (якщо налаштувати)

**Ресурси:**
- `azurerm_service_plan` — план розміщення
- `azurerm_linux_web_app` — сам додаток з Identity
- `azurerm_app_service_virtual_network_swift_connection` — VNet Integration
- `azurerm_private_endpoint` (pe_web) — Private Endpoint

---

### 2️⃣ **See what's happening**
**Файли:** `monitoring.tf`

✅ **Log Analytics Workspace** — центральне сховище
✅ **Application Insights** — моніторинг додатку
✅ **Автоматична інтеграція** — connection string в app_settings

**Що бачите:**
- 📊 Performance графіки
- 🔴 Exceptions з stack traces
- 📈 SQL queries та їх час виконання
- 🔍 Custom logs (console.log)
- 👤 Кількість користувачів

**Ресурси:**
- `azurerm_log_analytics_workspace` — зберігання логів (30 днів)
- `azurerm_application_insights` — моніторинг

---

### 3️⃣ **Where to put our containers**
**Файли:** `acr.tf`, `rbac.tf`

✅ **Azure Container Registry** — приватний Docker registry
✅ **Premium SKU** — Private Endpoint підтримка
✅ **Admin disabled** — тільки Azure AD / Managed Identity
✅ **AcrPull role** — App Service може витягувати образи

**Workflow:**
```bash
developer → build → tag → push to ACR → App Service pull
                            ↑ Managed Identity (no password)
```

**Ресурси:**
- `azurerm_container_registry` — реєстр образів
- `azurerm_private_endpoint` (pe_acr) — приватний доступ
- `azurerm_role_assignment` (acr_pull) — права для App Service

---

### 4️⃣ **Safe for passwords**
**Файли:** `keyvault.tf`, `rbac.tf`

✅ **Key Vault** — спеціалізоване сховище секретів
✅ **Public access disabled** — тільки через VNet
✅ **Purge protection** — захист від випадкового видалення
✅ **RBAC** — App Service має доступ читати секрети

**Що зберігаємо:**
- API ключі (SendGrid, Stripe, OpenAI)
- Connection strings (якщо треба)
- OAuth токени
- SSL сертифікати

**Ресурси:**
- `azurerm_key_vault` — сейф
- `azurerm_private_endpoint` (pe_kv) — приватний доступ
- `azurerm_role_assignment` (kv_secrets_user) — права для App Service

---

### 5️⃣ **Our private territory**
**Файли:** `network.tf`, `dns.tf`

✅ **Virtual Network** — ізольована мережа (10.10.0.0/16)
✅ **2 Subnets:**
  - `snet-app` (10.10.1.0/24) — делегована App Service
  - `snet-private-endpoints` (10.10.2.0/24) — приватні IP всіх сервісів

✅ **Private DNS Zones** — резолвінг приватних адрес
✅ **Весь трафік всередині Azure** — не виходить в інтернет

**Архітектура:**
```
Internet
   ↓ (заблоковано)
VNet (10.10.0.0/16)
   ├─ snet-app (10.10.1.0/24)
   │   └─ App Service (VNet Integration)
   │
   └─ snet-pe (10.10.2.0/24)
       ├─ SQL Server → 10.10.2.5
       ├─ Key Vault → 10.10.2.6
       ├─ ACR → 10.10.2.7
       └─ Storage → 10.10.2.8
```

**Ресурси:**
- `azurerm_virtual_network` — мережа
- `azurerm_subnet` (x2) — підмережі
- `azurerm_private_dns_zone` (x5) — DNS зони
- `azurerm_private_dns_zone_virtual_network_link` (x5) — прив'язка до VNet

---

### 6️⃣ **Where to store data**
**Файли:** `sql.tf`

✅ **Azure SQL Server** — managed SQL
✅ **SQL Database** — ваша база даних (bestrongdb)
✅ **S0 tier** — Standard ($15/міс)
✅ **Public access disabled** — тільки з VNet
✅ **Private Endpoint** — приватний IP

**Чому SQL Server:**
- Розробники знають T-SQL ✅
- Знайомий стек (Entity Framework)
- SQL Server Management Studio
- Automatic backups

**Connection:**
```javascript
// Managed Identity — без паролів!
authentication: {
  type: 'azure-active-directory-msi-app-service'
}
```

**Ресурси:**
- `azurerm_mssql_server` — SQL сервер
- `azurerm_mssql_database` — база даних
- `azurerm_private_endpoint` (pe_sql) — приватний доступ

---

### 7️⃣ **For user files**
**Файли:** `storage_files.tf`, `appservice.tf`

✅ **Azure Storage Account** — сховище
✅ **File Share** — SMB share (100 GB)
✅ **Public access disabled** — тільки з VNet
✅ **Mounted в App Service** — `/mounts/uploads`

**Як використовувати:**
```javascript
// Просто як локальна папка!
const fs = require('fs').promises;
await fs.writeFile('/mounts/uploads/photo.jpg', buffer);
await fs.readFile('/mounts/uploads/photo.jpg');
```

**Переваги:**
- Не треба SDK
- Shared між інстансами App Service
- Backups
- 100 GB квота

**Ресурси:**
- `azurerm_storage_account` — сховище
- `azurerm_storage_share` — file share
- `azurerm_private_endpoint` (pe_file) — приватний доступ
- Storage mount в `azurerm_linux_web_app`

---

### 8️⃣ **For your Terraform magic**
**Файли:** `backend.tf`

✅ **Remote Backend** — стан в Azure Storage
✅ **State Locking** — захист від одночасних змін
✅ **Не на ноутбуці** — у хмарі
✅ **Командна робота** — всі бачать однаковий стан

**Як працює:**
```bash
# Перша команда будь-кого:
terraform init
# Terraform: "Завантажую стан з Azure Storage..."

terraform apply
# Terraform: "Блокую стан... Застосовую зміни... Розблоковую"

# Якщо хтось ще працює:
terraform apply
# Error: State locked by roman@example.com
```

**Що потрібно створити вручну (один раз):**
```bash
az group create --name rg-bestrong-tfstate --location northeurope
az storage account create --name stbestrongtfstate001 --resource-group rg-bestrong-tfstate
az storage container create --name tfstate --account-name stbestrongtfstate001
```

**Ресурси:**
- Terraform backend конфігурація
- Storage Account `stbestrongtfstate001` (створюється вручну)
- Blob Container `tfstate`

---

## 📊 Схема інфраструктури

```
┌─────────────────────────────────────────────────────────────┐
│                         Internet                            │
└────────────────────────┬────────────────────────────────────┘
                         │ (❌ Blocked)
                         ↓
┌─────────────────────────────────────────────────────────────┐
│  VNet: 10.10.0.0/16 (bestrong-dev)                         │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Subnet: snet-app (10.10.1.0/24)                      │  │
│  │                                                        │  │
│  │   ┌─────────────────────────────────────┐            │  │
│  │   │ Azure App Service (Linux)           │            │  │
│  │   │ - Docker: nginx:latest              │            │  │
│  │   │ - SystemAssigned Identity ����        │            │  │
│  │   │ - Mounted: /mounts/uploads          │            │  │
│  │   │ - VNet Integration                  │────────┐   │  │
│  │   └─────────────────────────────────────┘        │   │  │
│  └──────────────────────────────────────────────────│───┘  │
│                                                       │      │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Subnet: snet-private-endpoints (10.10.2.0/24)      │    │
│  │                                                      │    │
│  │  ┌──────────────────┐  ┌──────────────────┐        │    │
│  │  │ SQL Server PE    │  │ Key Vault PE     │        │    │
│  │  │ 10.10.2.5        │  │ 10.10.2.6        │        │    │
│  │  └────────┬─────────┘  └────────┬─────────┘        │    │
│  │           │                     │                   │    │
│  │  ┌────────▼─────────┐  ┌───────▼──────────┐        │    │
│  │  │ ACR PE           │  │ Storage Files PE │        │    │
│  │  │ 10.10.2.7        │  │ 10.10.2.8        │◄───────┼────┘
│  │  └──────────────────┘  └──────────────────┘        │
│  └──────────────────────────────────────────────────────┘
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Private DNS Zones:                                   │  │
│  │ - privatelink.database.windows.net                   │  │
│  │ - privatelink.vaultcore.azure.net                    │  │
│  │ - privatelink.azurecr.io                             │  │
│  │ - privatelink.file.core.windows.net                  │  │
│  │ - privatelink.azurewebsites.net                      │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘

          ┌──────────────────────────────────┐
          │ Зовні VNet (managed services)    │
          │                                  │
          │ ┌──────────────────────────────┐ │
          │ │ Application Insights         │ │
          │ │ + Log Analytics Workspace    │ │
          │ └──────────────────────────────┘ │
          └──────────────────────────────────┘

          ┌──────────────────────────────────┐
          │ Remote State (manual setup)      │
          │                                  │
          │ ┌──────────────────────────────┐ │
          │ │ Storage: stbestrongtfstate001│ │
          │ │ Container: tfstate            │ │
          │ │ File: bestrong-infra.tfstate  │ │
          │ └──────────────────────────────┘ │
          └──────────────────────────────────┘
```

---

## 💰 Приблизна вартість (місячно)

| Ресурс | SKU/Tier | Ціна/міс |
|--------|----------|----------|
| App Service Plan | B1 (Basic) | $13 |
| SQL Database | S0 (Standard) | $15 |
| Container Registry | Premium | $40 |
| Storage Account | Standard LRS | $2 |
| Key Vault | Standard | $0.03 (операції) |
| Log Analytics | PerGB2018 (5GB free) | $0-10 |
| Application Insights | (входить в LAW) | - |
| VNet | - | Безкоштовно |
| Private Endpoints | x4 | $0.01 x 4 = $0.04 |
| **TOTAL** | | **~$70-80/міс** |

**Оптимізація для dev:**
- App Service: вимкнено → **-$13**
- ACR: можна Basic → **-$35**
- SQL: можна Serverless → **$5-15** замість $15
- **Dev Total: ~$20-30/міс**

---

## 🚀 Команди для роботи

```bash
# Ініціалізація (перший раз)
terraform init

# Перевірка конфігурації
terraform validate

# Переглянути план
terraform plan

# Застосувати зміни
terraform apply

# Переглянути outputs
terraform output

# Видалити все
terraform destroy

# Форматування коду
terraform fmt -recursive

# Список ресурсів у стані
terraform state list

# Імпорт існуючого ресурсу
terraform import azurerm_resource_group.rg /subscriptions/.../resourceGroups/rg-name
```

---

## 🔒 Безпека - що реалізовано

✅ **Ізоляція мережі**
- Всі сервіси в приватній VNet
- Public access disabled на всіх ресурсах

✅ **Identity-based auth**
- Managed Identity замість паролів
- RBAC для контролю доступу

✅ **Секрети**
- Key Vault для чутливих даних
- terraform.tfvars в .gitignore

✅ **Encryption**
- Azure автоматично шифрує:
  - SQL Database (at rest)
  - Storage Account (at rest)
  - Трафік (TLS in transit)

✅ **Моніторинг**
- Application Insights для аудиту
- Log Analytics для логів доступу

✅ **Backup & Recovery**
- SQL: automatic backups (7-35 днів)
- Key Vault: soft delete (7 днів)
- Storage: можна включити versioning

---

## 📚 Подальші покращення

### Коротко-строкові (1-2 тижні):
1. ✅ **Включити App Service** — коли квота буде
2. ✅ **Додати Azure AD auth** — для додатку
3. ✅ **Налаштувати CI/CD** — GitHub Actions / Azure DevOps
4. ✅ **Додати Application Gateway** — WAF, SSL offloading

### Середньо-строкові (1-2 місяці):
5. ✅ **Окремий VNet для prod** — dev/prod ізоляція
6. ✅ **Azure Front Door** — CDN, глобальний load balancing
7. ✅ **Managed Identity для SQL** — без admin password
8. ✅ **Automation Account** — автоматичні задачі

### Довго-строкові (3+ місяці):
9. ✅ **Multi-region deployment** — високадоступність
10. ✅ **Azure Kubernetes Service** — якщо потрібна контейнерна оркестрація
11. ✅ **Azure API Management** — API gateway, rate limiting
12. ✅ **Azure Cosmos DB** — якщо потрібна NoSQL

---

## ❓ FAQ

**Q: Чому App Service, а не Kubernetes?**
A: Для вашого випадку App Service простіше та дешевше. AKS потрібен, коли:
- 10+ мікросервісів
- Складна оркестрація
- Custom networking requirements

**Q: Чому Premium ACR?**
A: Потрібен для Private Endpoint. Для dev можна Basic + public access.

**Q: Як підключитися до SQL для міграцій?**
A: 
- Azure Data Studio через Azure Portal
- Або тимчасово включити public access + firewall rule
- Або VPN до VNet

**Q: Чому random_string suffix?**
A: Key Vault має глобально унікальне ім'я. Suffix гарантує це.

**Q: Скільки коштує якщо вимкнути App Service?**
A: ~$20-30/міс (ACR Basic, SQL Serverless)

**Q: Як масштабувати?**
A: 
- App Service: змінити SKU на S1, S2, P1V2 тощо
- SQL: змінити sku_name на S1, S2, P1 тощо
- Автоматично: налаштувати autoscaling rules

---

## 📞 Контакти та підтримка

**Документація:**
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure App Service](https://learn.microsoft.com/en-us/azure/app-service/)
- [Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/)

**Корисні команди:**
```bash
# Azure CLI
az account show
az resource list
az webapp log tail --name app-bestrong-dev --resource-group rg-bestrong-dev

# Terraform
terraform show
terraform state list
terraform state show azurerm_linux_web_app.app
```

---

**Створено:** Грудень 2024  
**Версія:** 1.0  
**Автор:** Infrastructure as Code для BeStrong Project

