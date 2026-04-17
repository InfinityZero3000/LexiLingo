importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyDxb89kPDmWalE3fx8Jlo45pNYMfpe-Q5I",
  authDomain: "lexilingo-88492.firebaseapp.com",
  projectId: "lexilingo-88492",
  storageBucket: "lexilingo-88492.firebasestorage.app",
  messagingSenderId: "432329288238",
  appId: "1:432329288238:web:f34e2fdf685d5b8a718dbf",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const { title, body, icon } = payload.notification ?? {};
  self.registration.showNotification(title ?? "LexiLingo", {
    body: body ?? "",
    icon: icon ?? "/icons/Icon-192.png",
  });
});
