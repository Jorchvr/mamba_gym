// app/assets/javascripts/clients_new.js
(function(){
  const invBtn   = document.getElementById('inventory-open-btn');
  const camBtn   = document.getElementById('camera-open-btn');
  const refBtn   = document.getElementById('camera-refresh-btn');
  const capBtn   = document.getElementById('camera-capture-btn');
  const closeBtn = document.getElementById('camera-close-btn');

  const fileInput = document.getElementById('client_photo_input');
  const preview   = document.getElementById('photo-preview');
  const img       = document.getElementById('photo-img');

  const panel  = document.getElementById('camera-panel');
  const video  = document.getElementById('camera-video');
  const canvas = document.getElementById('camera-canvas');

  const camSelect = document.getElementById('camera-select');
  const statusEl  = document.getElementById('camera-status');

  const LS_KEY = 'preferred_camera_device_id';
  let stream = null;

  function setStatus(msg) {
    if (statusEl) statusEl.textContent = msg || '';
  }

  function stopStream() {
    if (stream) {
      stream.getTracks().forEach(t => t.stop());
      stream = null;
    }
    if (video) video.srcObject = null;
  }

  async function listCameras() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) {
      setStatus('Tu navegador no soporta enumerateDevices().');
      return;
    }
    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      const videos = devices.filter(d => d.kind === 'videoinput');

      camSelect.innerHTML = '<option value="">Selecciona una cámara…</option>';
      videos.forEach(d => {
        const opt = document.createElement('option');
        opt.value = d.deviceId;
        opt.textContent = d.label || `Cámara (${d.deviceId.slice(0,6)}…)`;
        camSelect.appendChild(opt);
      });

      const saved = localStorage.getItem(LS_KEY);
      if (saved && videos.some(v => v.deviceId === saved)) {
        camSelect.value = saved;
      } else if (videos.length === 1) {
        camSelect.value = videos[0].deviceId;
      }
      setStatus(videos.length ? '' : 'No hay cámaras disponibles.');
    } catch (e) {
      setStatus('No se pudieron listar las cámaras: ' + e.message);
    }
  }

  async function ensurePermission() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      setStatus('Tu navegador no soporta getUserMedia().');
      return;
    }
    try {
      const tmp = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
      tmp.getTracks().forEach(t => t.stop());
    } catch (_) {}
  }

  async function openCameraWith(deviceId) {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      setStatus('Tu navegador no soporta getUserMedia().');
      return;
    }
    stopStream();
    const constraints = deviceId
      ? { video: { deviceId: { exact: deviceId } }, audio: false }
      : { video: true, audio: false };

    try {
      stream = await navigator.mediaDevices.getUserMedia(constraints);
      video.srcObject = stream;
      panel.style.display = 'block';
      await video.play().catch(()=>{});
      setStatus('');
      if (deviceId) localStorage.setItem(LS_KEY, deviceId);
    } catch (err) {
      let msg = "No se pudo acceder a la cámara: " + err.name;
      if (err.name === 'NotAllowedError') {
        msg += " (permiso denegado). Concede permiso al navegador.";
      } else if (err.name === 'NotFoundError' || err.name === 'OverconstrainedError') {
        msg += " (dispositivo no disponible). Revisa que la cámara esté conectada y seleccionada.";
      } else if (err.name === 'NotReadableError') {
        msg += " (la cámara está en uso por otra aplicación). Cierra Zoom/OBS/etc.";
      }
      setStatus(msg);
      panel.style.display = 'none';
    }
  }

  // Inventario (archivo)
  if (invBtn && fileInput) {
    invBtn.addEventListener('click', () => fileInput.click());
  }
  if (fileInput && img && preview) {
    fileInput.addEventListener('change', (e) => {
      const file = e.target.files && e.target.files[0];
      if (!file) { preview.style.display = 'none'; img.src = ''; return; }
      const reader = new FileReader();
      reader.onload = (ev) => {
        img.src = ev.target.result;
        preview.style.display = 'block';
      };
      reader.readAsDataURL(file);
    });
  }

  // Cámara
  if (camBtn) {
    camBtn.addEventListener('click', async () => {
      setStatus('Abriendo cámara…');
      await ensurePermission();
      await listCameras();
      const selected = camSelect.value || localStorage.getItem(LS_KEY);
      await openCameraWith(selected);
    });
  }

  if (refBtn) {
    refBtn.addEventListener('click', async () => {
      await ensurePermission();
      await listCameras();
    });
  }

  if (camSelect) {
    camSelect.addEventListener('change', async (e) => {
      const id = e.target.value;
      await openCameraWith(id);
    });
  }

  if (closeBtn) {
    closeBtn.addEventListener('click', () => {
      stopStream();
      panel.style.display = 'none';
      setStatus('Cámara cerrada.');
    });
  }

  if (capBtn) {
    capBtn.addEventListener('click', () => {
      if (!video.videoWidth) return;
      const w = video.videoWidth;
      const h = video.videoHeight;
      canvas.width = w; canvas.height = h;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(video, 0, 0, w, h);
      canvas.toBlob((blob) => {
        if (!blob) return;
        const file = new File([blob], "camera_capture.jpg", { type: "image/jpeg", lastModified: Date.now() });
        const dt = new DataTransfer();
        dt.items.add(file);
        fileInput.files = dt.files;

        const url = URL.createObjectURL(blob);
        img.src = url;
        preview.style.display = 'block';
      }, "image/jpeg", 0.92);
    });
  }

  // Limpieza al navegar
  window.addEventListener('beforeunload', stopStream);
  document.addEventListener('turbo:before-cache', stopStream);
})();
