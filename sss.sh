<?php
// ==================== НАЧАЛО ФАЙЛА ==================== [cite: 42]
session_start(); // Инициализация сессии [cite: 45]

// Параметры подключения к БД [cite: 50]
$host = 'localhost'; [cite: 51]
$dbname = 'file_storage'; [cite: 54]
$user = 'root'; // Измените на вашего пользователя MySQL [cite: 57]
$pass = '';     // Измените на ваш пароль MySQL [cite: 60]

try {
    $pdo = new PDO("mysql:host=$host;dbname=$dbname;charset=utf8mb4", $user, $pass); [cite: 66]
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION); [cite: 70]
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC); [cite: 74]
} catch (PDOException $e) {
    die("Ошибка подключения к базе данных: " . $e->getMessage()); [cite: 81]
}

// ==================== ФУНКЦИИ ШИФРОВАНИЯ И УКРАШЕНИЯ ====================

// Функция шифрования файла [cite: 85]
function encryptFile($fileData, $key) { [cite: 86]
    $iv = openssl_random_pseudo_bytes(16); // Генерация вектора инициализации [cite: 90]
    $encrypted = openssl_encrypt($fileData, 'AES-256-CBC', $key, OPENSSL_RAW_DATA, $iv); [cite: 96]
    return base64_encode($iv . $encrypted); // Склеиваем IV и шифртекст, переводим в Base64 [cite: 104]
}

// Функция расшифрования файла [cite: 109]
function decryptFile($encryptedData, $key) { [cite: 110]
    $data = base64_decode($encryptedData); [cite: 114]
    $iv = substr($data, 0, 16); // Извлекаем первые 16 байт (IV) [cite: 117]
    $encrypted = substr($data, 16); // Извлекаем сам шифртекст [cite: 121]
    return openssl_decrypt($encrypted, 'AES-256-CBC', $key, OPENSSL_RAW_DATA, $iv); [cite: 123]
}

// Функция форматирования размера файла [cite: 132]
function formatFileSize($bytes) { [cite: 133]
    if ($bytes === 0) return '0 B'; [cite: 136]
    $k = 1024; [cite: 138]
    $sizes = ['B', 'KB', 'MB', 'GB']; [cite: 140]
    $i = floor(log($bytes) / log($k)); [cite: 143]
    return round($bytes / pow($k, $i), 2) . ' ' . $sizes[$i]; [cite: 152]
}

// Инициализация системных сообщений [cite: 158]
$message = ''; [cite: 159]
$messageType = ''; [cite: 162]

// ==================== ОБРАБОТКА ДЕЙСТВИЙ (КОНТРОЛЛЕРЫ) ====================

// Выход из системы [cite: 166]
if (isset($_GET['logout'])) { [cite: 167]
    session_destroy(); [cite: 170]
    header('Location: index.php'); [cite: 173]
    exit; [cite: 177]
}

// Вход в систему [cite: 4]
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['login'])) {
    $username = trim($_POST['username']); [cite: 4]
    $password = $_POST['password']; [cite: 4]

    if (empty($username) || empty($password)) { [cite: 4]
        $message = 'Введите имя пользователя и пароль'; [cite: 4]
        $messageType = 'warning'; [cite: 4]
    } else {
        $stmt = $pdo->prepare("SELECT * FROM users WHERE username = ?"); [cite: 4]
        $stmt->execute([$username]); [cite: 4]
        $user_row = $stmt->fetch(); [cite: 4]

        if ($user_row && password_verify($password, $user_row['password_hash'])) { [cite: 5]
            $_SESSION['user_id'] = $user_row['id']; [cite: 5]
            $_SESSION['username'] = $user_row['username']; [cite: 5]
            header('Location: index.php'); [cite: 5]
            exit; [cite: 5]
        } else {
            $message = 'Неверное имя пользователя или пароль'; [cite: 5]
            $messageType = 'danger'; [cite: 5]
        }
    }
}

// Загрузка и шифрование файла [cite: 180]
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['file'])) { [cite: 181]
    if (!isset($_SESSION['user_id'])) { [cite: 185]
        $message = 'Необходимо авторизоваться'; [cite: 188]
        $messageType = 'danger'; [cite: 189]
    } elseif (empty($_POST['key'])) { [cite: 192]
        $message = 'Введите ключ шифрования'; [cite: 195]
        $messageType = 'warning'; [cite: 196]
    } elseif ($_FILES['file']['error'] !== UPLOAD_ERR_OK) { [cite: 198]
        $message = 'Ошибка загрузки файла'; [cite: 202]
        $messageType = 'danger'; [cite: 203]
    } else {
        $uploadDir = 'uploads/' . $_SESSION['user_id'] . '/'; [cite: 206]
        if (!file_exists($uploadDir)) { [cite: 210]
            mkdir($uploadDir, 0777, true); [cite: 212]
        }
        $fileName = time() . '_' . basename($_FILES['file']['name']); [cite: 217]
        $filePath = $uploadDir . $fileName; [cite: 223]
        
        $fileData = file_get_contents($_FILES['file']['tmp_name']); [cite: 226]
        $encryptedData = encryptFile($fileData, $_POST['key']); [cite: 231]
        
        if (file_put_contents($filePath, $encryptedData) !== false) { [cite: 234]
            $stmt = $pdo->prepare("INSERT INTO files (user_id, description, file_path, file_name, file_size, file_type) VALUES (?, ?, ?, ?, ?, ?)"); [cite: 238]
            $stmt->execute([
                $_SESSION['user_id'], [cite: 243]
                $_POST['description'], [cite: 245]
                $filePath, [cite: 247]
                $_FILES['file']['name'], [cite: 249]
                $_FILES['file']['size'], [cite: 251]
                $_FILES['file']['type'] [cite: 254]
            ]);
            $message = 'Файл успешно загружен и зашифрован!'; [cite: 257]
            $messageType = 'success'; [cite: 258]
        } else {
            $message = 'Не удалось сохранить файл на сервере.';
            $messageType = 'danger';
        }
    }
}

// Удаление файла [cite: 263]
if (isset($_GET['delete'])) { [cite: 264]
    if (!isset($_SESSION['user_id'])) { [cite: 267]
        $message = 'Необходимо авторизоваться'; [cite: 269]
        $messageType = 'danger'; [cite: 270]
    } else {
        $stmt = $pdo->prepare("SELECT file_path FROM files WHERE id = ? AND user_id = ?"); [cite: 273]
        $stmt->execute([$_GET['delete'], $_SESSION['user_id']]); [cite: 277]
        $file = $stmt->fetch(); [cite: 279]

        if ($file) { [cite: 282]
            if (file_exists($file['file_path'])) { [cite: 284]
                unlink($file['file_path']); // Удаляем файл с диска [cite: 287]
            }
            $stmt = $pdo->prepare("DELETE FROM files WHERE id = ? AND user_id = ?"); [cite: 290]
            $stmt->execute([$_GET['delete'], $_SESSION['user_id']]); [cite: 292]
            $message = 'Файл удален'; [cite: 294]
            $messageType = 'success'; [cite: 295]
        } else {
            $message = 'Файл не найден или доступ запрещен';
            $messageType = 'danger';
        }
    }
}

// Скачивание РАСШИФРОВАННОГО файла
if (isset($_GET['download_decrypted'])) {
    if (!isset($_SESSION['user_id'])) { [cite: 1]
        die('Необходимо авторизоваться'); [cite: 1]
    }

    if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['decrypt_key'])) { [cite: 1]
        $stmt = $pdo->prepare("SELECT * FROM files WHERE id = ? AND user_id = ?"); [cite: 1]
        $stmt->execute([$_GET['download_decrypted'], $_SESSION['user_id']]); [cite: 1]
        $file = $stmt->fetch(); [cite: 1]

        if ($file && file_exists($file['file_path'])) { [cite: 1]
            $encryptedData = file_get_contents($file['file_path']); [cite: 1]
            $decryptedData = decryptFile($encryptedData, $_POST['decrypt_key']); [cite: 1]

            if ($decryptedData === false) { [cite: 1]
                $_SESSION['message'] = 'Неверный ключ шифрования!'; [cite: 1]
                $_SESSION['messageType'] = 'danger'; [cite: 1]
                header('Location: index.php'); [cite: 1]
                exit; [cite: 1]
            } else { // Успешная расшифровка — отдаем в браузер [cite: 1]
                header('Content-Type: ' . $file['file_type']); [cite: 1]
                header('Content-Disposition: attachment; filename="' . $file['file_name'] . '"'); [cite: 1]
                header('Content-Length: ' . strlen($decryptedData)); [cite: 1]
                echo $decryptedData; [cite: 1]
                exit; [cite: 1]
            }
        } else {
            $_SESSION['message'] = 'Файл не найден!'; [cite: 2]
            $_SESSION['messageType'] = 'danger'; [cite: 2]
            header('Location: index.php'); [cite: 2]
            exit; [cite: 2]
        }
    } else {
        $showDecryptForm = true; [cite: 2]
        $downloadFileId = $_GET['download_decrypted']; [cite: 2]
    }
}

// Скачивание ЗАШИФРОВАННОГО файла (в сыром виде) [cite: 2]
if (isset($_GET['download_encrypted'])) { [cite: 2]
    if (!isset($_SESSION['user_id'])) { [cite: 2]
        die('Необходимо авторизоваться'); [cite: 2]
    }

    $stmt = $pdo->prepare("SELECT * FROM files WHERE id = ? AND user_id = ?"); [cite: 2]
    $stmt->execute([$_GET['download_encrypted'], $_SESSION['user_id']]); [cite: 2]
    $file = $stmt->fetch(); [cite: 2]

    if ($file && file_exists($file['file_path'])) { [cite: 3]
        $encryptedData = file_get_contents($file['file_path']); [cite: 3]
        $encryptedFileName = '[ENCRYPTED]_' . pathinfo($file['file_name'], PATHINFO_FILENAME) . '.enc'; [cite: 3]

        header('Content-Type: application/octet-stream'); [cite: 3]
        header('Content-Disposition: attachment; filename="' . $encryptedFileName . '"'); [cite: 3]
        header('Content-Length: ' . strlen($encryptedData)); [cite: 3]
        header('X-Encrypted-File: true'); [cite: 3]
        header('X-Original-Name: ' . $file['file_name']); [cite: 3]
        echo $encryptedData; [cite: 3]
        exit; [cite: 3]
    } else {
        $message = 'Файл не найден'; [cite: 3]
        $messageType = 'danger'; [cite: 3]
    }
}

// Восстановление межстраничных уведомлений из сессии [cite: 5]
if (isset($_SESSION['message'])) { [cite: 5]
    $message = $_SESSION['message']; [cite: 5]
    $messageType = $_SESSION['messageType']; [cite: 5]
    unset($_SESSION['message'], $_SESSION['messageType']); [cite: 5]
}
?>
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Безопасное файловое хранилище</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body {
            background: linear-gradient(135deg, #f5f7fa 0%, #e9edf2 100%);
            min-height: 100vh;
            padding: 40px 0;
            font-family: 'Segoe UI', Roboto, sans-serif;
        }
        .card {
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.05);
            border: none;
            background: #ffffff;
            margin-bottom: 25px;
        }
        .card-header {
            background: linear-gradient(135deg, #ffffff 0%, #f8f9fa 100%);
            color: #2c3e50;
            border-top-left-radius: 15px !important;
            border-top-right-radius: 15px !important;
            padding: 20px;
            font-weight: 600;
        }
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border: none;
        }
        .btn-primary:hover {
            background: linear-gradient(135deg, #764ba2 0%, #667eea 100%);
        }
    </style>
</head>
<body>
<div class="container">
    <div class="row justify-content-center">
        <div class="col-md-10">
            
            <h2 class="text-center mb-4 text-secondary"><i class="fa-solid rel="stylesheet""></i> Защищенное Облако</h2>

            <?php if (!empty($message)): ?>
                <div class="alert alert-<?= htmlspecialchars($messageType) ?> alert-dismissible fade show" role="alert">
                    <?= htmlspecialchars($message) ?>
                    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
                </div>
            <?php endif; ?>

            <?php if (isset($showDecryptForm) && $showDecryptForm): ?>
                <div class="card border-warning">
                    <div class="card-header bg-warning text-dark">📜 Требуется ключ расшифрования</div>
                    <div class="card-body">
                        <form method="POST" action="index.php?download_decrypted=<?= intval($downloadFileId) ?>">
                            <div class="mb-3">
                                <label class="form-label">Введите секретный ключ для этого файла:</label>
                                <input type="password" name="decrypt_key" class="form-control" required autocomplete="off">
                            </div>
                            <button type="submit" class="btn btn-success"><i class="fa-solid fa-download"></i> Расшифровать и Скачать</button>
                            <a href="index.php" class="btn btn-secondary">Отмена</a>
                        </form>
                    </div>
                </div>
            <?php endif; ?>

            <?php if (!isset($_SESSION['user_id'])): ?>
                <div class="card">
                    <div class="card-header"><i class="fa-solid fa-lock"></i> Авторизация в системе</div>
                    <div class="card-body">
                        <form method="POST" action="index.php">
                            <input type="hidden" name="login" value="1">
                            <div class="row align-items-center">
                                <div class="col-md-4 mb-2">
                                    <input type="text" name="username" class="form-control" placeholder="Логин (admin)" required>
                                </div>
                                <div class="col-md-4 mb-2">
                                    <input type="password" name="password" class="form-control" placeholder="Пароль (password)" required>
                                </div>
                                <div class="col-md-4 mb-2">
                                    <button type="submit" class="btn btn-primary w-100">Войти</button>
                                </div>
                            </div>
                        </form>
                    </div>
                </div>
            <?php else: ?>
                <div class="card bg-light">
                    <div class="card-body d-flex justify-content-between align-items-center">
                        <span><i class="fa-solid fa-user-shield text-success"></i> Вы вошли как: <strong><?= htmlspecialchars($_SESSION['username']) ?></strong></span>
                        <a href="index.php?logout=1" class="btn btn-outline-danger btn-sm"><i class="fa-solid fa-right-from-bracket"></i> Выйти</a>
                    </div>
                </div>

                <div class="card">
                    <div class="card-header"><i class="fa-solid fa-file-arrow-up"></i> Загрузить новый файл в шифрованное хранилище</div>
                    <div class="card-body">
                        <form method="POST" action="index.php" enctype="multipart/form-data">
                            <div class="row">
                                <div class="col-md-6 mb-3">
                                    <label class="form-label">Выбор файла</label>
                                    <input type="file" name="file" class="form-control" required>
                                </div>
                                <div class="col-md-6 mb-3">
                                    <label class="form-label">Ключ шифрования (AES-256)</label>
                                    <input type="password" name="key" class="form-control" placeholder="Придумайте стойкий ключ" required autocomplete="off">
                                </div>
                                <div class="mb-3">
                                    <label class="form-label">Описание файла (не шифруется)</label>
                                    <input type="text" name="description" class="form-control" placeholder="Краткое описание содержимого">
                                </div>
                            </div>
                            <button type="submit" class="btn btn-primary"><i class="fa-solid fa-upload"></i> Зашифровать и загрузить</button>
                        </form>
                    </div>
                </div>

                <div class="card">
                    <div class="card-header"><i class="fa-solid fa-folder-open"></i> Ваши защищенные файлы</div>
                    <div class="card-body">
                        <?php
                        $stmt = $pdo->prepare("SELECT * FROM files WHERE user_id = ? ORDER BY id DESC");
                        $stmt->execute([$_SESSION['user_id']]);
                        $files = $stmt->fetchAll();

                        if (count($files) === 0):
                        ?>
                            <p class="text-muted text-center my-4">У вас пока нет загруженных файлов.</p>
                        <?php else: ?>
                            <div class="table-responsive">
                                <table class="table table-hover align-middle">
                                    <thead class="table-light">
                                        <tr>
                                            <th>Оригинальное имя</th>
                                            <th>Описание</th>
                                            <th>Размер</th>
                                            <th>Тип данных</th>
                                            <th class="text-end">Действия</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <?php foreach ($files as $f): ?>
                                            <tr>
                                                <td><strong><?= htmlspecialchars($f['file_name']) ?></strong></td>
                                                <td><span class="text-muted"><?= htmlspecialchars($f['description'] ?: '—') ?></span></td>
                                                <td><code class="text-dark"><?= formatFileSize($f['file_size']) ?></code></td>
                                                <td><span class="badge bg-secondary"><?= htmlspecialchars($f['file_type']) ?></span></td>
                                                <td class="text-end">
                                                    <div class="btn-group" role="group">
                                                        <a href="index.php?download_decrypted=<?= $f['id'] ?>" class="btn btn-sm btn-success" title="Расшифровать и скачать"><i class="fa-solid fa-unlock"></i> Скачать</a>
                                                        <a href="index.php?download_encrypted=<?= $f['id'] ?>" class="btn btn-sm btn-outline-secondary" title="Скачать зашифрованный оригинал (.enc)"><i class="fa-solid fa-file-shield"></i> .ENC</a>
                                                        <a href="index.php?delete=<?= $f['id'] ?>" class="btn btn-sm btn-danger" onclick="return confirm('Вы уверены, что хотите удалить этот файл с сервера?')" title="Удалить"><i class="fa-solid fa-trash"></i></a>
                                                    </div>
                                                </td>
                                            </tr>
                                        <?php endforeach; ?>
                                    </tbody>
                                </table>
                            </div>
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
