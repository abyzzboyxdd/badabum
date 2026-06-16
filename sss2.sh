CREATE DATABASE IF NOT EXISTS `file_storage` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `file_storage`;

-- Таблица пользователей
CREATE TABLE IF NOT EXISTS `users` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `username` VARCHAR(50) NOT NULL UNIQUE,
  `password_hash` VARCHAR(255) NOT NULL
) ENGINE=InnoDB;

-- Таблица файлов
CREATE TABLE IF NOT EXISTS `files` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT NOT NULL,
  `description` TEXT,
  `file_path` VARCHAR(255) NOT NULL,
  `file_name` VARCHAR(255) NOT NULL,
  `file_size` INT NOT NULL,
  `file_type` VARCHAR(100) NOT NULL,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Хэш пароля 'password' для тестового пользователя 'admin'
INSERT INTO `users` (`username`, `password_hash`) 
VALUES ('admin', '$2y$10$Z3g7Xh9K7Z2mE5rT8YBcOu3vF1wA6zPqSjKDeLoR4mN2bV1xYZaTu')
ON DUPLICATE KEY UPDATE `username`=`username`;
