import React from "react";
import { Link } from "react-router-dom";

export const NoAccessPage = () => (
  <div className="center-page">
    <div className="center-card">
      <h1>Không có quyền truy cập</h1>
      <p>Hệ thống chưa cấp quyền Admin hoặc Super Admin cho tài khoản này.</p>
      <Link to="/login" className="primary-button">
        Quay lại đăng nhập
      </Link>
    </div>
  </div>
);
