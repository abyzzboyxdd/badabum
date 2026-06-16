<?php
// ==================== НАЧАЛО ФАЙЛА ====================
if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

// Параметры подключения к базе данных
$host = 'localhost';
$dbname = 'file_storage';
$user = 'root';
$pass = '';

try {
    $pdo = new PDO("mysql:host=$host;dbname=$dbname;charset=utf8mb4", $user, $pass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
} catch (PDOException $e) {
    die("Ошибка подключения к базе данных: " . $e->getMessage());
}

// ==================== ФУНКЦИИ ШИФРОВАНИЯ И ПРЕДСТАВЛЕНИЯ ====================
function encryptFile($fileData, $key) {
    $iv = openssl_random_pseudo_bytes(16);
    $encrypted = openssl_encrypt($fileData, 'AES-256-CBC', $key, OPENSSL_RAW_DATA, $iv);
    return base64_encode($iv . $encrypted);
}

function decryptFile($encryptedData, $key) {
    $data = base64_decode($encryptedData);
    $iv = substr($data, 0, 16);
    $encrypted = substr($data, 16);
    return openssl_decrypt($encrypted, 'AES-256-CBC', $key, OPENSSL_RAW_DATA, $iv);
}

function formatFileSize($bytes) {
    if ($bytes === 0) return '0 B';
    $k = 1024;
    $sizes = ['B', 'KB', 'MB', 'GB'];
    $i = floor(log($bytes) / log($k));
    return round($bytes / pow($k, $i), 2) . ' ' . $sizes[$i];
}

$message = "";
$messageType = "";

// ==================== ЛОГИКА ВЫХОДА (LOGOUT) ====================
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

// ==================== УДАЛЕНИЕ ФАЙЛА (ИСПРАВЛЕННАЯ СТРОКА 105) ====================
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
                $_SESSION['message'] = 'Неверный ключ шифрования!';
                $_SESSION['messageType'] = 'danger';
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
            $_SESSION['message'] = 'Файл не найден';
            $_SESSION['messageType'] = 'danger';
            header('Location: index.php');
            exit;
        }
    } else {
        $showDecryptForm = true;
        $downloadFileId = $_GET['download_decrypted'];
    }
}

// ==================== АВТОРИЗАЦИЯ И АВТО-РЕГИСТРАЦИЯ ====================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['login'])) {
    $username = trim($_POST['username']);
    $password = $_POST['password'];
    
    if (!empty($username) && !empty($password)) {
        $stmt = $pdo->prepare("SELECT * FROM users WHERE username = ?");
        $stmt->execute([$username]);
        $user = $stmt->fetch();
        
        if ($user && password_verify($password, $user['password_hash'])) {
            $_SESSION['user_id'] = $user['id'];
            $_SESSION['username'] = $user['username'];
            header('Location: index.php');
            exit;
        } elseif (!$user) {
            // Если пользователя нет, регистрируем на лету
            $hash = password_hash($password, PASSWORD_DEFAULT);
            $stmt = $pdo->prepare("INSERT INTO users (username, password_hash) VALUES (?, ?)");
            $stmt->execute([$username, $hash]);
            
            $_SESSION['user_id'] = $pdo->lastInsertId();
            $_SESSION['username'] = $username;
            header('Location: index.php');
            exit;
        } else {
            $message = 'Неверный пароль';
            $messageType = 'danger';
        }
    }
}

// Восстановление флеш-сообщений из сессии
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
    <title>Безопасное хранилище данных</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body { background: #f5f7fa; padding-top: 50px; font-family: sans-serif; }
        .card { border-radius: 15px; box-shadow: 0 4px 15px rgba(0,0,0,0.05); border: none; margin-bottom: 20px; }
    </style>
</head>
<body>
<div class="container">
    <div class="row justify-content-center">
        <div class="col-md-8">
            
            <?php if (!empty($message)): ?>
                <div class="alert alert-<?= $messageType ?> alert-dismissible fade show">
                    <?= htmlspecialchars($message) ?>
                    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                </div>
            <?php endif; ?>

            <?php if (!isset($_SESSION['user_id'])): ?>
                <div class="card mx-auto" style="max-width: 400px; margin-top: 50px;">
                    <div class="card-header text-center bg-white"><h4>Вход в систему</h4></div>
                    <div class="card-body">
                        <form method="POST">
                            <input type="hidden" name="login" value="1">
                            <div class="mb-3">
                                <label class="form-label">Логин</label>
                                <input type="text" name="username" class="form-control" required>
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Пароль</label>
                                <input type="password" name="password" class="form-control" required>
                            </div>
                            <button type="submit" class="btn btn-primary w-100">Войти или Зарегистрироваться</button>
                        </form>
                    </div>
                </div>
            
            <?php else: ?>
                <div class="d-flex justify-content-between align-items-center mb-4">
                    <h4>Личный кабинет: <?= htmlspecialchars($_SESSION['username']) ?></h4>
                    <a href="?logout=1" class="btn btn-danger btn-sm">Выйти</a>
                </div>

                <?php if (isset($showDecryptForm)): ?>
                    <div class="card border-warning mb-4">
                        <div class="card-header bg-warning text-dark">Ввод ключа безопасности</div>
                        <div class="card-body">
                            <form method="POST" action="?download_decrypted=<?= $downloadFileId ?>">
                                <div class="input-group">
                                    <input type="password" name="decrypt_key" class="form-control" placeholder="Введите ключ шифрования для этого файла" required>
                                    <button type="submit" class="btn btn-success">Подтвердить и скачать</button>
                                </div>
                            </form>
                        </div>
                    </div>
                <?php endif; ?>

                <div class="card">
                    <div class="card-header bg-white"><h5>Загрузить и зашифровать файл</h5></div>
                    <div class="card-body">
                        <form method="POST" enctype="multipart/form-data">
                            <div class="row">
                                <div class="col-md-6 mb-3">
                                    <label class="form-label">Файл</label>
                                    <input type="file" name="file" class="form-control" required>
                                </div>
                                <div class="col-md-6 mb-3">
                                    <label class="form-label">Ключ (AES-256)</label>
                                    <input type="password" name="key" class="form-control" placeholder="Ключ шифрования" required>
                                </div>
                                <div class="col-md-12 mb-3">
                                    <label class="form-label">Описание (не шифруется)</label>
                                    <input type="text" name="description" class="form-control" placeholder="Краткое описание">
                                </div>
                            </div>
                            <button type="submit" class="btn btn-primary">Загрузить</button>
                        </form>
                    </div>
                </div>

                <div class="card">
                    <div class="card-header bg-white"><h5>Ваши защищенные файлы</h5></div>
                    <div class="card-body">
                        <?php
                        $stmt = $pdo->prepare("SELECT * FROM files WHERE user_id = ? ORDER BY id DESC");
                        $stmt->execute([$_SESSION['user_id']]);
                        $files = $stmt->fetchAll();
                        
                        if (empty($files)): ?>
                            <p class="text-muted text-center">Вы пока не загрузили ни одного файла.</p>
                        <?php else: ?>
                            <?php foreach ($files as $f): ?>
                                <div class="p-3 border-bottom d-flex justify-content-between align-items-center">
                                    <div>
                                        <strong><i class="fa-regular fa-file me-2 text-secondary"></i><?= htmlspecialchars($f['file_name']) ?></strong>
                                        <br><small class="text-muted">Размер: <?= formatFileSize($f['file_size']) ?> | Тип: <?= htmlspecialchars($f['file_type']) ?></small>
                                        <?php if (!empty($f['description'])): ?>
                                            <br><small class="text-info">Описание: <?= htmlspecialchars($f['description']) ?></small>
                                        <?php endif; ?>
                                    </div>
                                    <div>
                                        <a href="?download_decrypted=<?= $f['id'] ?>" class="btn btn-sm btn-success"><i class="fa-solid fa-download"></i> Скачать</a>
                                        <a href="?delete=<?= $f['id'] ?>" class="btn btn-sm btn-danger" onclick="return confirm('Удалить файл из хранилища?')"><i class="fa-solid fa-trash"></i></a>
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
