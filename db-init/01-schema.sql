-- Тестовая схема для проверки approval-хука.

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    total NUMERIC(10, 2),
    status TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO users (email, name) VALUES
    ('alice@example.com', 'Alice'),
    ('bob@example.com', 'Bob'),
    ('carol@example.com', 'Carol');

INSERT INTO orders (user_id, total, status) VALUES
    (1, 99.50, 'paid'),
    (1, 14.20, 'pending'),
    (2, 250.00, 'paid'),
    (3, 7.99, 'cancelled');
