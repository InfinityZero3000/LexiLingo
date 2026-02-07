import React from "react";
import { Link } from "react-router-dom";

export const NotFoundPage = () => (
  <div className="center-page">
    <div className="center-card">
      <h1>Không tìm thấy trang</h1>
      <p>Đường dẫn bạn yêu cầu không tồn tại.</p>
      <Link to="/" className="primary-button">
        Về dashboard
      </Link>
    </div>
  </div>
);
