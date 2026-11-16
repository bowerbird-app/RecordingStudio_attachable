const RASTER_TYPES = new Set(["image/jpeg", "image/jpg", "image/png", "image/webp", "image/gif"])

export function dimensionErrorForFile(file, limits) {
  if (!rasterImage(file)) return Promise.resolve(null)

  return readNaturalSize(file).then((size) => {
    if (!size) return null
    if (!exceedsCaps(size, limits)) return null

    return limits.message || fallbackMessage(limits)
  })
}

function rasterImage(file) {
  const type = String(file?.type || "").toLowerCase().split(";")[0].trim()
  return RASTER_TYPES.has(type)
}

function readNaturalSize(file) {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file)
    const image = new Image()
    const finish = (size) => {
      URL.revokeObjectURL(url)
      resolve(size)
    }

    image.onload = () => {
      const width = image.naturalWidth
      const height = image.naturalHeight
      finish(width > 0 && height > 0 ? { width, height } : null)
    }
    image.onerror = () => finish(null)
    image.src = url
  })
}

function exceedsCaps(size, limits) {
  const pixels = Number(limits.maxPixels)
  const side = Number(limits.maxLongestSide)
  if (pixels > 0 && size.width * size.height > pixels) return true
  if (side > 0 && Math.max(size.width, size.height) > side) return true

  return false
}

function fallbackMessage(limits) {
  const pixels = Number(limits.maxPixels).toLocaleString()
  const side = Number(limits.maxLongestSide).toLocaleString()
  return `This image is too big. Keep it under ${pixels} pixels, and under ${side} pixels on the longest side.`
}
