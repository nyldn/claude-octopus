"""
Authentication module with SQL injection vulnerability
Source: Adapted from OWASP examples for benchmarking
"""

import sqlite3
from flask import Flask, request, session

app = Flask(__name__)
app.secret_key = 'dev_key_12345'  # Issue: Hardcoded secret key

class UserAuth:
    def __init__(self, db_path='users.db'):
        self.db_path = db_path
        self.init_db()

    def init_db(self):
        """Initialize database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY,
                username TEXT NOT NULL,
                password TEXT NOT NULL,
                role TEXT DEFAULT 'user'
            )
        ''')
        conn.commit()
        conn.close()

    def login(self, username, password):
        """
        Authenticate user - VULNERABLE TO SQL INJECTION
        Issue 1: String concatenation in SQL query (CWE-89)
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # CRITICAL: SQL Injection vulnerability
        query = f"SELECT * FROM users WHERE username = '{username}' AND password = '{password}'"
        cursor.execute(query)

        user = cursor.fetchone()
        conn.close()

        if user:
            # Issue 2: Plain text password storage (CWE-256)
            # Issue 3: Session token is just user ID (CWE-331)
            session['user_id'] = user[0]
            session['role'] = user[3]
            return True
        return False

    def check_admin(self, user_id):
        """
        Check if user is admin
        Issue 4: SQL Injection in admin check
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # CRITICAL: Another SQL injection point
        query = f"SELECT role FROM users WHERE id = {user_id}"
        cursor.execute(query)

        result = cursor.fetchone()
        conn.close()

        return result and result[0] == 'admin'

@app.route('/login', methods=['POST'])
def login_endpoint():
    """
    Login endpoint
    Issue 5: No rate limiting (CWE-799)
    Issue 6: No CSRF protection
    """
    username = request.form.get('username', '')
    password = request.form.get('password', '')

    auth = UserAuth()

    # Issue 7: No input validation
    if auth.login(username, password):
        return {'status': 'success', 'user_id': session['user_id']}
    else:
        # Issue 8: Information disclosure in error message
        return {'status': 'error', 'message': f'Invalid credentials for user {username}'}

@app.route('/admin', methods=['GET'])
def admin_panel():
    """
    Admin panel
    Issue 9: Insecure direct object reference
    """
    user_id = request.args.get('user_id')  # Issue 10: User can specify their own ID

    auth = UserAuth()
    if auth.check_admin(user_id):
        return {'status': 'admin_access_granted'}
    return {'status': 'access_denied'}

if __name__ == '__main__':
    # Issue 11: Debug mode in production
    app.run(debug=True, host='0.0.0.0')  # Issue 12: Binds to all interfaces
