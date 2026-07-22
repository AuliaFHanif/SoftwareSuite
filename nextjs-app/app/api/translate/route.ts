import { NextResponse } from 'next/server'
import {createWorker} from "tesseract.js";

function inputPrompt(
    TEXT: string,
    SOURCE_LANG: string,
    SOURCE_CODE: string,
    TARGET_LANG: string,
    TARGET_CODE: string
): string {
  return `You are a professional ${SOURCE_LANG} (${SOURCE_CODE}) to ${TARGET_LANG} (${TARGET_CODE}) translator. Your goal is to accurately convey the meaning and nuances of the original ${SOURCE_LANG} text/inside images while adhering to ${TARGET_LANG} grammar, vocabulary, and cultural sensitivities. Produce only the ${TARGET_LANG} translation, without any additional explanations or commentary. Please translate the following ${SOURCE_LANG} text/images into ${TARGET_LANG}:


${TEXT}`;
}

async function ocrMultiLang(imageData: string) {
  const langCodes = 'eng+chi_sim+jpn'
  const worker = await createWorker(langCodes)

  try {
    const base64Data = imageData.replace(/^data:image\/\w+;base64,/, '')
    const buffer = Buffer.from(base64Data, 'base64')

    const { data: { text } } = await worker.recognize(buffer)
    await worker.terminate()
    return text
  } catch (error) {
    await worker.terminate()
    console.error('OCR Error:', error)
    throw error
  }
}


export async function POST(request: Request) {
  const url = `${process.env.OLLAMA_URL || 'http://localhost:11434'}/api/generate`

  try {
    const body = await request.json()
    const { text, targetLang, targetCode, sourceLang, sourceCode, image } = body

    if (!text && !image) {
      return NextResponse.json({ error: 'Text or image is required' }, { status: 400 })
    }
    const hasImage = !!image

    let prompt: string
    if (hasImage) {
      const extractedText = await ocrMultiLang(image)
      console.log('OCR result:', extractedText)
      prompt = inputPrompt(extractedText, sourceLang, sourceCode, targetLang, targetCode)
    } else {
      prompt = inputPrompt(text, sourceLang, sourceCode, targetLang, targetCode)
    }

    const ollamaBody: Record<string, unknown> = {
      model: 'translategemma:4b',
      prompt: prompt,
      // images: hasImage ? [image] : undefined,
      stream: false
    }

    console.log('hasImage:', hasImage, 'image length:', image?.length)
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(ollamaBody)
    })

    const data = await response.json()
    return NextResponse.json({ translation: data.response })
  } catch (error) {
    console.error(error)
    return NextResponse.json({ error: 'Translation failed' }, { status: 500 })
  }
}

