const PROCESSABLE_CONTENT_TYPES = ["image/jpeg", "image/png", "image/webp"]
const MIN_DIMENSION_SCALE = 0.5
const MIN_ENCODER_QUALITY = 0.4
const MAX_ENCODING_ATTEMPTS = 6

export async function preprocessImageFile(file, options = {}) {
  const normalizedOptions = normalizeOptions(options)
  if (!shouldPreprocessImageFile(file, normalizedOptions)) {
    return { file, transformed: false }
  }

  const image = await loadImage(file)

  try {
    const { width, height } = imageDimensions(image)
    const constrainedDimensions = constrainDimensions({
      width,
      height,
      maxWidth: normalizedOptions.maxWidth,
      maxHeight: normalizedOptions.maxHeight
    })
    const shouldOptimizeForSize = normalizedOptions.maxBytes && file.size > normalizedOptions.maxBytes

    if (!shouldOptimizeForSize && constrainedDimensions.width === width && constrainedDimensions.height === height) {
      return { file, transformed: false }
    }

    const processedBlob = await encodeProcessedBlob({
      image,
      contentType: file.type,
      quality: normalizedOptions.quality,
      initialDimensions: constrainedDimensions,
      maxBytes: normalizedOptions.maxBytes
    })
    if (!processedBlob) {
      return { file, transformed: false }
    }

    if (processedBlob.size >= file.size && constrainedDimensions.width === width && constrainedDimensions.height === height) {
      return { file, transformed: false }
    }

    return {
      file: new File([processedBlob], file.name, { type: processedBlob.type || file.type, lastModified: file.lastModified }),
      transformed: true
    }
  } finally {
    cleanupLoadedImage(image)
  }
}

export function shouldPreprocessImageFile(file, options = {}) {
  const normalizedOptions = normalizeOptions(options)

  return Boolean(normalizedOptions.enabled) && PROCESSABLE_CONTENT_TYPES.includes(file.type)
}

function normalizeOptions(options) {
  return {
    enabled: Boolean(options.enabled),
    maxWidth: positiveInteger(options.maxWidth),
    maxHeight: positiveInteger(options.maxHeight),
    maxBytes: positiveInteger(options.maxBytes),
    quality: normalizedQuality(options.quality)
  }
}

async function encodeProcessedBlob({ image, contentType, quality, initialDimensions, maxBytes }) {
  const canvas = document.createElement("canvas")
  const context = canvas.getContext("2d")
  if (!context) return null

  let bestBlob = null
  let currentDimensions = initialDimensions
  let currentQuality = quality

  for (let attempt = 0; attempt < MAX_ENCODING_ATTEMPTS; attempt += 1) {
    canvas.width = currentDimensions.width
    canvas.height = currentDimensions.height
    context.clearRect(0, 0, canvas.width, canvas.height)
    context.drawImage(image, 0, 0, currentDimensions.width, currentDimensions.height)

    const blob = await canvasToBlob(canvas, contentType, currentQuality)
    if (!blob) break

    if (!bestBlob || blob.size < bestBlob.size) {
      bestBlob = blob
    }

    if (!maxBytes || blob.size <= maxBytes) {
      return blob
    }

    const nextQuality = nextEncodingQuality(contentType, currentQuality)
    if (nextQuality < currentQuality) {
      currentQuality = nextQuality
      continue
    }

    const nextDimensions = nextEncodingDimensions(currentDimensions, blob.size, maxBytes)
    if (nextDimensions.width === currentDimensions.width && nextDimensions.height === currentDimensions.height) {
      break
    }

    currentDimensions = nextDimensions
  }

  return bestBlob
}

function nextEncodingQuality(contentType, currentQuality) {
  if (!usesEncoderQuality(contentType) || currentQuality <= MIN_ENCODER_QUALITY) {
    return currentQuality
  }

  return Math.max(MIN_ENCODER_QUALITY, Math.round(currentQuality * 0.85 * 100) / 100)
}

function nextEncodingDimensions(dimensions, currentSize, maxBytes) {
  const targetRatio = Math.sqrt(maxBytes / currentSize) * 0.95
  const scale = Math.min(0.9, Math.max(MIN_DIMENSION_SCALE, targetRatio))

  return {
    width: Math.max(1, Math.floor(dimensions.width * scale)),
    height: Math.max(1, Math.floor(dimensions.height * scale))
  }
}

function positiveInteger(value) {
  const number = Number(value)
  return Number.isFinite(number) && number > 0 ? Math.round(number) : null
}

function normalizedQuality(value) {
  const number = Number(value)
  if (!Number.isFinite(number)) return 0.82

  return Math.min(Math.max(number, 0.1), 1)
}

function loadImage(file) {
  return new Promise((resolve, reject) => {
    const objectUrl = URL.createObjectURL(file)
    const image = new Image()
    image.dataset.objectUrl = objectUrl
    image.onload = () => resolve(image)
    image.onerror = () => reject(new Error(`Could not decode ${file.name}`))
    image.src = objectUrl
  })
}

function cleanupLoadedImage(image) {
  const objectUrl = image?.dataset?.objectUrl
  if (objectUrl) URL.revokeObjectURL(objectUrl)
}

function imageDimensions(image) {
  return {
    width: image.naturalWidth || image.width,
    height: image.naturalHeight || image.height
  }
}

function constrainDimensions({ width, height, maxWidth, maxHeight }) {
  const widthScale = maxWidth ? maxWidth / width : 1
  const heightScale = maxHeight ? maxHeight / height : 1
  const scale = Math.min(widthScale, heightScale, 1)

  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale))
  }
}

function canvasToBlob(canvas, contentType, quality) {
  return new Promise((resolve) => {
    const encoderQuality = usesEncoderQuality(contentType) ? quality : undefined
    canvas.toBlob(resolve, contentType, encoderQuality)
  })
}

function usesEncoderQuality(contentType) {
  return ["image/jpeg", "image/webp"].includes(contentType)
}

export { PROCESSABLE_CONTENT_TYPES }