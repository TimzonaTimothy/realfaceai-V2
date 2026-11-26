// The transferred stream supplies decoded frames independently of the studio's
// video element painting. Keep at most one packet in flight to native output.
self.onmessage = async ({ data: { readable, url } }) => {
  const reader = readable.getReader();
  const socket = new WebSocket(url);
  const canvas = new OffscreenCanvas(1, 1);
  const context = canvas.getContext('2d', { willReadFrequently: true });
  let pending = false;
  let announced = false;
  let lastSentAt = -Infinity;

  socket.onmessage = () => {
    pending = false;
    if (!announced) {
      announced = true;
      self.postMessage('ready');
    }
  };
  socket.onclose = () => {
    self.postMessage('closed');
    void reader.cancel().catch(() => {});
  };
  socket.onerror = () => socket.close();

  try {
    while (true) {
      const { done, value: frame } = await reader.read();
      if (done) break;
      try {
        const now = performance.now();
        if (socket.readyState !== WebSocket.OPEN ||
            pending || now - lastSentAt < 30) continue;
        const scale = Math.min(1, 960 / frame.displayWidth, 540 / frame.displayHeight);
        const width = Math.max(1, Math.floor(frame.displayWidth * scale));
        const height = Math.max(1, Math.floor(frame.displayHeight * scale));
        if (canvas.width !== width) canvas.width = width;
        if (canvas.height !== height) canvas.height = height;
        context.drawImage(frame, 0, 0, width, height);
        const header = new DataView(new ArrayBuffer(8));
        header.setUint32(0, width, true);
        header.setUint32(4, height, true);
        const pixels = context.getImageData(0, 0, width, height).data;
        socket.send(new Blob([header.buffer, pixels]));
        pending = true;
        lastSentAt = now;
      } finally {
        frame.close();
      }
    }
  } catch (_) {
    self.postMessage('failed');
  } finally {
    await reader.cancel().catch(() => {});
    socket.close();
  }
};
