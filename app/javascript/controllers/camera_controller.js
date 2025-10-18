import { Controller } from "@hotwired/stimulus"

// Conecta con data-controller="camera" en el HTML
export default class extends Controller {
  static targets = [
    "status", "panel", "video", "canvas",
    "openBtn", "refreshBtn", "captureBtn", "closeBtn",
    "select", "fileInput", "previewImg", "previewBox"
  ]

  connect() {
    this.stream = null
    this.LS_KEY = "preferred_camera_device_id"
  }

  disconnect() {
    this.stopStream()
  }

  async open() {
    this.setStatus("Abriendo cámara…")
    await this.ensurePermission()
    await this.listCameras()
    const saved = localStorage.getItem(this.LS_KEY)
    const selected = this.selectTarget.value || saved
    await this.openWith(selected)
  }

  async refresh() {
    await this.ensurePermission()
    await this.listCameras()
  }

  async changeDevice(event) {
    const id = event.target.value
    await this.openWith(id)
  }

  close() {
    this.stopStream()
    this.panelTarget.style.display = "none"
    this.setStatus("Cámara cerrada.")
  }

  capture() {
    if (!this.videoTarget.videoWidth) {
      this.setStatus("Inicia la cámara antes de capturar.")
      return
    }
    const w = this.videoTarget.videoWidth
    const h = this.videoTarget.videoHeight
    this.canvasTarget.width = w
    this.canvasTarget.height = h
    const ctx = this.canvasTarget.getContext("2d")
    ctx.drawImage(this.videoTarget, 0, 0, w, h)

    this.canvasTarget.toBlob((blob) => {
      if (!blob) return
      const file = new File([blob], "camera_capture.jpg", { type: "image/jpeg", lastModified: Date.now() })
      const dt = new DataTransfer()
      dt.items.add(file)
      this.fileInputTarget.files = dt.files

      const url = URL.createObjectURL(blob)
      this.previewImgTarget.src = url
      this.previewBoxTarget.style.display = "block"
      this.setStatus("Foto capturada y adjuntada al formulario.")
    }, "image/jpeg", 0.92)
  }

  // ---------- helpers ----------
  setStatus(msg) {
    if (this.hasStatusTarget) this.statusTarget.textContent = msg || ""
  }

  stopStream() {
    if (this.stream) {
      this.stream.getTracks().forEach(t => t.stop())
      this.stream = null
    }
    if (this.hasVideoTarget) this.videoTarget.srcObject = null
  }

  async ensurePermission() {
    if (!navigator.mediaDevices?.getUserMedia) return
    try {
      const tmp = await navigator.mediaDevices.getUserMedia({ video: true, audio: false })
      tmp.getTracks().forEach(t => t.stop())
    } catch (_) {
      // si el usuario niega, seguimos; listaremos sin labels
    }
  }

  async listCameras() {
    if (!navigator.mediaDevices?.enumerateDevices) {
      this.setStatus("Tu navegador no soporta enumerateDevices().")
      return
    }
    const devices = await navigator.mediaDevices.enumerateDevices()
    const videos = devices.filter(d => d.kind === "videoinput")

    // limpia y carga opciones
    this.selectTarget.innerHTML = '<option value="">Selecciona una cámara…</option>'
    videos.forEach(d => {
      const opt = document.createElement("option")
      opt.value = d.deviceId
      opt.textContent = d.label || `Cámara (${d.deviceId.slice(0, 6)}…)`
      this.selectTarget.appendChild(opt)
    })

    // restaurar preferida
    const saved = localStorage.getItem(this.LS_KEY)
    if (saved && videos.some(v => v.deviceId === saved)) {
      this.selectTarget.value = saved
    } else if (videos.length === 1) {
      this.selectTarget.value = videos[0].deviceId
    }

    this.setStatus(videos.length ? "" : "No hay cámaras disponibles.")
  }

  async openWith(deviceId) {
    if (!navigator.mediaDevices?.getUserMedia) {
      this.setStatus("Tu navegador no soporta getUserMedia().")
      return
    }
    this.stopStream()

    const constraints = deviceId
      ? { video: { deviceId: { exact: deviceId } }, audio: false }
      : { video: true, audio: false }

    try {
      this.stream = await navigator.mediaDevices.getUserMedia(constraints)
      this.videoTarget.srcObject = this.stream
      this.panelTarget.style.display = "block"
      await this.videoTarget.play().catch(() => {})
      this.setStatus("")
      if (deviceId) localStorage.setItem(this.LS_KEY, deviceId)
    } catch (err) {
      let msg = "No se pudo acceder a la cámara: " + err.name
      if (err.name === "NotAllowedError") {
        msg += " (permiso denegado). Concede permiso al navegador."
      } else if (["NotFoundError", "OverconstrainedError"].includes(err.name)) {
        msg += " (dispositivo no disponible). Revisa que la cámara esté conectada/seleccionada."
      } else if (err.name === "NotReadableError") {
        msg += " (la cámara está en uso por otra aplicación). Cierra Zoom/Teams/OBS."
      }
      this.setStatus(msg)
      this.panelTarget.style.display = "none"
    }
  }
}
