// Push delivery for smashboard. Notification content is composed server-side
// and sent as the push payload, so the worker only has to render and route it.

self.addEventListener("push", (event) => {
  if (!event.data) return

  let payload
  try {
    payload = event.data.json()
  } catch {
    payload = { title: "smashboard", body: event.data.text() }
  }

  event.waitUntil(
    self.registration.showNotification(payload.title || "smashboard", {
      body: payload.body,
      icon: payload.icon || "/icon.png",
      badge: "/icon.png",
      tag: payload.tag,
      // Weather alerts and breaking news should stay put until acknowledged;
      // everything else can auto-dismiss.
      requireInteraction: Boolean(payload.require_interaction),
      data: { url: payload.url || "/" },
    })
  )
})

self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const url = event.notification.data?.url || "/"

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      // Focus an already-open board rather than stacking up tabs.
      for (const client of clients) {
        if (client.url.includes(url) && "focus" in client) return client.focus()
      }
      return self.clients.openWindow(url)
    })
  )
})
