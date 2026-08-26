// Registers the service worker and, once the user has granted permission,
// hands the resulting Web Push subscription to the server.
const VAPID_PUBLIC_KEY = document.querySelector("meta[name='vapid-public-key']")?.content

function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
  const raw = window.atob(base64)
  return Uint8Array.from([...raw].map((char) => char.charCodeAt(0)))
}

async function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) return null
  return navigator.serviceWorker.register("/service-worker.js", { scope: "/" })
}

export async function enablePushNotifications() {
  if (!VAPID_PUBLIC_KEY || !("PushManager" in window)) return false

  const registration = await registerServiceWorker()
  if (!registration) return false

  const permission = await Notification.requestPermission()
  if (permission !== "granted") return false

  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
  })

  await fetch("/push_subscriptions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content,
    },
    body: JSON.stringify(subscription.toJSON()),
  })

  return true
}

// Registering the worker early means push works on the next visit even if the
// user hasn't granted permission yet.
registerServiceWorker()
