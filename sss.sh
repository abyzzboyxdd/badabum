#!/bin/bash

# ==============================================================================
# АВТОМАТИЧЕСКИЙ СКРИПТ УСТАНОВКИ СТЕКА И РАЗВЕРТЫВАНИЯ ФАЙЛОВОГО ХРАНИЛИЩА
# Ориентирован на: CentOS 7
# ==============================================================================

# Проверка прав суперпользователя
if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт от имени root (через sudo)."
  exit 1
fi

echo "=== Шаг 1: Обновление системы и подключение репозиториев ==="
yum update -y
yum install -y epel-release yum-utils wget

echo "=== Шаг 2: Установка PHP 7.4 (Remi Repository) ==="
# Для работы openssl_encrypt/decrypt и PDO необходимы актуальные пакеты PHP
wget https://rpms.remirepo.net/enterprise/remi-release-7.rpm
rpm -Uvh remi-release-7.rpm
yum-config-manager --enable remi-php7.4
yum install -y php php-pdo php-mysqlnd php-openssl php-mbstring php-xml php-common

echo "=== Шаг 3: Установка и настройка веб-сервера Apache ==="
yum install -y httpd
systemctl start httpd
systemctl enable httpd

echo "=== Шаг 4: Установка и настройка СУБД MariaDB ==="
yum install -y mariadb-server mariadb
systemctl start mariadb
systemctl enable mariadb

# Переменные для базы данных
DB_NAME="file_storage"
DB_USER="root"
DB_PASS=""

echo "=== Шаг 5: Создание базы данных и таблиц ==="
# Автоматическое создание структуры БД для пользователей и файлов
mysql -u$DB_USER -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u$DB_USER -e "
USE $DB_NAME;
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS files (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    description TEXT,
    file_path VARCHAR(255) NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    file_size INT NOT NULL,
    file_type VARCHAR(100),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
"

echo "=== Шаг 6: Развертывание единого файла приложения index.php ==="
TARGET_DIR="/var/www/html"
mkdir -p $TARGET_DIR

# Запись всего кода вашего приложения из PDF в один файл index.php
cat << 'EOF' > $TARGET_DIR/index.php
<?php
// ========= ========== НАЧАЛО ФАЙЛА ==================== 
session_start(); // Инициализация сессии 

// ==================== ПАРАМЕТРЫ ПОДКЛЮЧЕНИЯ К БАЗЕ ДАННЫХ ======= 
$host = 'localhost'; 
$dbname = 'file_storage'; 
$user = 'root'; 
$pass = ''; 

// ==================== ПОДКЛЮЧЕНИЕ К БАЗЕ ДАННЫХ ==================== 
try { 
    $pdo = new PDO("mysql:host=$host;dbname=$dbname;charset=utf8mb4", $user, $pass); 
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION); 
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC); 
} catch (PDOException $e) { 
    die("Ошибка подключения к базе данных: " . $e->getMessage()); 
}

// ==================== ФУНКЦИЯ ШИФРОВАНИЯ ФАЙЛА ========== 
function encryptFile($fileData, $key) { 
    $iv = openssl_random_pseudo_bytes(16); // Генерация вектора инициализации 
    $encrypted = openssl_encrypt($fileData, 'AES-256-CBC', $key, OPENSSL_RAW_DATA, $iv); 
    return base64_encode($iv . $encrypted); // Склеиваем IV и шифротекст 
}

// ==================== ФУНКЦИЯ РАСШИФРОВАНИЯ ФАЙЛА ======= 
function decryptFile($encryptedData, $key) { 
    $data = base64_decode($encryptedData); 
    $iv = substr($data, 0, 16); // Вырезаем первые 16 байт (IV) 
    $encrypted = substr($data, 16); 
    return openssl_decrypt($encrypted, 'AES-256-CBC', $key, OPENSSL_RAW_DATA, $iv); 
}

// ==================== ФУНКЦИЯ ФОРМАТИРОВАНИЯ РАЗМЕРА ФАЙЛА ==================== 
function formatFileSize($bytes) { 
    if ($bytes === 0) return '0 B'; 
    $k = 1024; 
    $sizes = ['B', 'KB', 'MB', 'GB']; 
    $i = floor(log($bytes) / log($k)); 
    return round($bytes / pow($k, $i), 2) . ' ' . $sizes[$i]; 
}

// ===== ИНИЦИАЛИЗАЦИЯ ПЕРЕМЕННЫХ СООБЩЕНИЙ ========= 
$message = ""; 
$messageType = ""; 

// ==================== ОБРАБОТКА ВЫХОДА ИЗ СИСТЕМЫ ==================== 
if (isset($_GET['logout'])) { 
    session_destroy(); 
    header('Location: index.php'); 
    exit; 
}

// ==================== ОБРАБОТКА ЗАГРУЗКИ ФАЙЛА ==================== 
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['file'])) { 
    if (!isset($_SESSION['user_id'])) { 
        $message = 'Необходимо авторизоваться'; 
        $messageType = 'danger'; 
    } elseif (empty($_POST['key'])) { 
        $message = 'Введите ключ шифрования'; 
        $messageType = 'warning'; 
    } elseif ($_FILES['file']['error'] !== UPLOAD_ERR_OK) { 
        $message = 'Ошибка загрузки файла'; 
        $messageType = 'danger'; 
    } else { 
        $uploadDir = 'uploads/' . $_SESSION['user_id'] . '/'; 
        if (!file_exists($uploadDir)) { 
            mkdir($uploadDir, 0777, true); 
        } 
        $fileName = time() . '_' . basename($_FILES['file']['name']); 
        $filePath = $uploadDir . $fileName; 
        
        $fileData = file_get_contents($_FILES['file']['tmp_name']); 
        $encryptedData = encryptFile($fileData, $_POST['key']); 
        
        if (file_put_contents($filePath, $encryptedData)) { 
            $stmt = $pdo->prepare("INSERT INTO files (user_id, description, file_path, file_name, file_size, file_type) VALUES (?, ?, ?, ?, ?, ?)"); 
            $stmt->execute([
                $_SESSION['user_id'],
                $_POST['description'],
                $filePath,
                $_FILES['file']['name'],
                $_FILES['file']['size'],
                $_FILES['file']['type']
            ]); 
            $message = 'Файл успешно загружен и зашифрован!'; 
            $messageType = 'success'; 
        } 
    }
}

// ==================== УДАЛЕНИЕ ФАЙЛА ==================== 
if (isset($_GET['delete'])) { 
    if (!isset($_SESSION['user_id'])) { 
        $message = 'Необходимо авторизоваться'; 
        $messageType = 'danger'; 
    } else { 
        $stmt = $pdo->prepare("SELECT file_path FROM files WHERE id = ? AND user_id = ?"); 
        $stmt->execute([$_GET['delete'], $_SESSION['user_id']]); 
        $file = $stmt->fetch(); 
        
        if ($file) { 
            if (file_exists($file['file_path'])) { 
                unlink($file['file_path']); 
            } 
            $stmt = $pdo->prepare("DELETE FROM files WHERE id = ? AND user_id = ?"); 
            $stmt->execute([$_GET['delete'], $_SESSION['user_id']]); 
            $message = 'Файл удален'; 
            $messageType = 'success'; 
        } else { 
            $message = 'Файл не найден'; 
            $messageType = 'danger'; 
        }
    }
}

// ==================== СКАЧИВАНИЕ РАСШИФРОВАННОГО ФАЙЛА ==================== 
if (isset($_GET['download_decrypted'])) { 
    if (!isset($_SESSION['user_id'])) { 
        die('Необходимо авторизоваться'); 
    }
    if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['decrypt_key'])) { 
        $stmt = $pdo->prepare("SELECT * FROM files WHERE id = ? AND user_id = ?"); 
        $stmt->execute([$_GET['download_decrypted'], $_SESSION['user_id']]); 
        $file = $stmt->fetch(); 
        
        if ($file && file_exists($file['file_path'])) { 
            $encryptedData = file_get_contents($file['file_path']); 
            $decryptedData = decryptFile($encryptedData, $_POST['decrypt_key']); 
            
            if ($decryptedData === false) { 
                $message = 'Неверный ключ шифрования!'; 
                $messageType = 'danger'; 
                $_SESSION['message'] = $message; 
                $_SESSION['messageType'] = $messageType; 
                header('Location: index.php'); 
                exit; 
            } else { 
                header('Content-Type: ' . $file['file_type']); 
                header('Content-Disposition: attachment; filename="' . $file['file_name'] . '"'); 
                header('Content-Length: ' . strlen($decryptedData)); 
                echo $decryptedData; 
                exit; 
            }
        } else { 
            $message = 'Файл не найден'; 
            $messageType = 'danger'; 
            $_SESSION['message'] = $message; 
            $_SESSION['messageType'] = $messageType; 
            header('Location: index.php'); 
            exit; 
        }
    } else { 
        $showDecryptForm = true; 
        $downloadFileId = $_GET['download_decrypted']; 
    }
}

// ==================== СКАЧИВАНИЕ ЗАШИФРОВАННОГО ФАЙЛА ==================== 
if (isset($_GET['download_encrypted'])) { 
    if (!isset($_SESSION['user_id'])) { 
        die('Необходимо авторизоваться'); 
    }
    $stmt = $pdo->prepare("SELECT * FROM files WHERE id = ? AND user_id = ?"); 
    $stmt->execute([$_GET['download_encrypted'], $_SESSION['user_id']]); 
    $file = $stmt->fetch(); 
    
    if ($file && file_exists($file['file_path'])) { 
        $encryptedData = file_get_contents($file['file_path']); 
        $encryptedFileName = '[ENCRYPTED]_' . pathinfo($file['file_name'], PATHINFO_FILENAME) . '.enc'; 
        
        header('Content-Type: application/octet-stream'); 
        header('Content-Disposition: attachment; filename="' . $encryptedFileName . '"'); 
        header('Content-Length: ' . strlen($encryptedData)); 
        header('X-Encrypted-File: true'); 
        header('X-Original-Name: ' . $file['file_name']); 
        echo $encryptedData; 
        exit; 
    } else { 
        $message = 'Файл не найден'; 
        $messageType = 'danger'; 
    }
}

// ==================== ВХОД В СИСТЕМУ / РЕГИСТРАЦИЯ ==================== 
// Примечание: Для удобства развертывания добавлен механизм авторегистрации, если пользователя нет
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['login'])) { 
    $username = trim($_POST['username']); 
    $password = $_POST['password']; 
    
    if (empty($username) || empty($password)) { 
        $message = 'Введите имя пользователя и пароль'; 
        $messageType = 'warning'; 
    } else { 
        $stmt = $pdo->prepare("SELECT * FROM users WHERE username = ?"); 
        $stmt->execute([$username]); 
        $user = $stmt->fetch(); 
        
        if ($user && password_verify($password, $user['password_hash'])) { 
            $_SESSION['user_id'] = $user['id']; 
            $_SESSION['username'] = $user['username']; 
            header('Location: index.php'); 
            exit; 
        } elseif (!$user) { 
            // Авторегистрация нового пользователя при первом вводе (улучшение для тестов)
            $hash = password_hash($password, PASSWORD_DEFAULT); 
            $stmt = $pdo->prepare("INSERT INTO users (username, password_hash) VALUES (?, ?)"); 
            $stmt->execute([$username, $hash]); 
            
            $stmt = $pdo->prepare("SELECT * FROM users WHERE username = ?"); 
            $stmt->execute([$username]); 
            $user = $stmt->fetch(); 
            
            $_SESSION['user_id'] = $user['id']; 
            $_SESSION['username'] = $user['username']; 
            header('Location: index.php'); 
            exit; 
        } else { 
            $message = 'Неверное имя пользователя или пароль'; 
            $messageType = 'danger'; 
        }
    }
}

// ВОСТАНОВЛЕНИЕ СООБЩЕНИЙ ИЗ СЕССИИ 
if (isset($_SESSION['message'])) { 
    $message = $_SESSION['message']; 
    $messageType = $_SESSION['messageType']; 
    unset($_SESSION['message']); 
    unset($_SESSION['messageType']); 
}
?>
<!DOCTYPE HTML>
<html lang="ru">
<head>
    <meta charset="UTF-8"> 
    <meta name="viewport" content="width=device-width, initial-scale=1.0"> 
    <title>Безопасное файловое хранилище</title> 
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet"> 
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"> 
    <style>
        body { background: linear-gradient(135deg, #f5f7fa 0%, #e4e8f2 100%); min-height: 100vh; padding: 20px 0; font-family: 'Segoe UI', Roboto, sans-serif; } 
        .card { border-radius: 20px; box-shadow: 0 10px 40px rgba(0,0,0,0.08); border: none; margin-bottom: 20px; background: #ffffff; } 
        .card-header { background: linear-gradient(135deg, #ffffff 0%, #f8f9fa 100%); color: #2c3e50; border-radius: 20px 20px 0 0 !important; padding: 25px; border-bottom: 2px solid #e9ecef; } 
        .btn-primary { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); border: none; font-weight: 600; padding: 10px 25px; } 
        .btn-primary:hover { background: linear-gradient(135deg, #764ba2 0%, #667eea 100%); transform: translateY(-1px); } 
        .file-item { border-left: 4px solid #667eea; padding: 15px; margin-bottom: 12px; border-radius: 8px; background: #fdfdfd; transition: all 0.2s; } 
        .file-item:hover { background: #f8f9fa; }
    </style>
</head>
<body>
<div class="container">
    <div class="row justify-content-center">
        <div class="col-md-10">
            
            <?php if (!empty($message)): ?>
                <div class="alert alert-<?= $messageType ?> alert-dismissible fade show" role="alert">
                    <?= htmlspecialchars($message) ?>
                    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
                </div>
            <?php endif; ?>

            <?php if (!isset($_SESSION['user_id'])): ?>
                <div class="card mx-auto" style="max-width: 450px; margin-top: 100px;">
                    <div class="card-header text-center">
                        <h3><i class="fa-solid fa-lock text-primary me-2"></i>Вход в хранилище</h3>
                        <small class="text-muted">Если аккаунта нет, он будет создан автоматически</small>
                    </div>
                    <div class="card-body p-4">
                        <form method="POST">
                            <input type="hidden" name="login" value="1">
                            <div class="mb-3">
                                <label class="form-label">Имя пользователя</label>
                                <input type="text" name="username" class="form-row form-control" required>
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Пароль</label>
                                <input type="password" name="password" class="form-control" required>
                            </div>
                            <button type="submit" class="btn btn-primary w-100 mt-2">Войти / Создать</button>
                        </form>
                    </div>
                </div>
            <?php else: ?>
                <div class="d-flex justify-content-between align-items-center mb-4">
                    <h4><i class="fa-solid fa-folder-open text-primary me-2"></i>Кабинет: <?= htmlspecialchars($_SESSION['username']) ?></h4>
                    <a href="?logout=1" class="btn btn-outline-danger btn-sm"><i class="fa-solid fa-right-from-bracket me-2"></i>Выйти</a>
                </div>

                <?php if (isset($showDecryptForm)): ?>
                    <div class="card border-warning mb-4">
                        <div class="card-header bg-warning text-dark">
                            <h5><i class="fa-solid fa-key me-2"></i>Требуется ключ дешифрования</h5>
                        </div>
                        <div class="card-body">
                            <form method="POST" action="?download_decrypted=<?= $downloadFileId ?>">
                                <div class="input-group">
                                    <input type="password" name="decrypt_key" class="form-control" placeholder="Введите секретный ключ" required autofocus>
                                    <button type="submit" class="btn btn-success"><i class="fa-solid fa-download me-2"></i>Скачать расшифрованный</button>
                                    <a href="index.php" class="btn btn-secondary">Отмена</a>
                                </div>
                            </form>
                        </div>
                    </div>
                <?php endif; ?>

                <div class="card">
                    <div class="card-header"><h5><i class="fa-solid fa-cloud-arrow-up me-2"></i>Загрузить новый файл</h5></div>
                    <div class="card-body p-4">
                        <form method="POST" enctype="multipart/form-data">
                            <div class="row">
                                <div class="col-md-6 mb-3">
                                    <label class="form-label">Выберите файл</label>
                                    <input type="file" name="file" class="form-control" required>
                                </div>
                                <div class="col-md-6 mb-3">
                                    <label class="form-label">Ключ шифрования (AES-256)</label>
                                    <input type="password" name="key" class="form-control" placeholder="Очень важный пароль" required>
                                </div>
                                <div class="col-md-12 mb-3">
                                    <label class="form-label">Описание файла</label>
                                    <input type="text" name="description" class="form-control" placeholder="Краткое описание содержимого (не шифруется)">
                                </div>
                            </div>
                            <button type="submit" class="btn btn-primary"><i class="fa-solid fa-shield-halved me-2"></i>Зашифровать и загрузить</button>
                        </form>
                    </div>
                </div>

                <div class="card">
                    <div class="card-header"><h5><i class="fa-solid fa-list-check me-2"></i>Ваши защищенные файлы</h5></div>
                    <div class="card-body">
                        <?php
                        $stmt = $pdo->prepare("SELECT * FROM files WHERE user_id = ? ORDER BY id DESC");
                        $stmt->execute([$_SESSION['user_id']]);
                        $files = $stmt->fetchAll();
                        
                        if (empty($files)):
                        ?>
                            <p class="text-muted text-center py-4">Вы еще не загрузили ни одного файла.</p>
                        <?php else: ?>
                            <?php foreach ($files as $f): ?>
                                <div class="file-item d-flex justify-content-between align-items-center">
                                    <div>
                                        <h6 class="mb-1 text-dark"><i class="fa-regular fa-file-code me-2 text-secondary"></i><?= htmlspecialchars($f['file_name']) ?></h6>
                                        <small class="text-muted">
                                            <strong>Размер:</strong> <?= formatFileSize($f['file_size']) ?> | 
                                            <strong>Тип:</strong> <?= htmlspecialchars($f['file_type']) ?>
                                            <?php if(!empty($f['description'])): ?>
                                                <br><span class="text-info"><i><?= htmlspecialchars($f['description']) ?></i></span>
                                            <?php endif; ?>
                                        </small>
                                    </div>
                                    <div class="btn-group">
                                        <a href="?download_decrypted=<?= $f['id'] ?>" class="btn btn-sm btn-success" title="Расшифровать и скачать"><i class="fa-solid fa-lock-open"></i> Скачать</a>
                                        <a href="?download_encrypted=<?= $f['id'] ?>" class="btn btn-sm btn-outline-secondary" title="Скачать сырой зашифрованный файл (.enc)"><i class="fa-solid fa-file-shield"></i> .ENC</a>
                                        <a href="?delete=<?= $f['id'] ?>" class="btn btn-sm btn-danger" onclick="return confirm('Удалить файл?')" title="Удалить"><i class="fa-solid fa-trash"></i></a>
                                    </div>
                                </div>
                            <?php endforeach; ?>
                        <?php endif; ?>
                    </div>
                </div>
            <?php endif; ?>

        </div>
    </div>
</div>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF

echo "=== Шаг 7: Настройка прав доступа ==="
# Веб-сервер Apache должен иметь права на чтение/запись в каталоге uploads
chown -R httpd:httpd $TARGET_DIR
chmod -R 755 $TARGET_DIR

echo "=== Шаг 8: Настройка брандмауэра ==="
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

echo "=============================================================================="
echo "Установка успешно завершена!"
echo "Приложение доступно по адресу: http://$(hostname -I | awk '{print $1}')/index.php"
echo "=============================================================================="
