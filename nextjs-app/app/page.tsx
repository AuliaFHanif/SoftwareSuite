"use client"
import CountrySelect from "@/components/country-select";
import { useState, useEffect } from "react"
import { X, Copy, Check, ImageIcon } from "lucide-react";
import {Textarea} from "@/components/ui/textarea";

export default function Home() {
    const [sourceCountry, setSourceCountry] = useState("detect")
    const [sourceCountryCode, setSourceCountryCode] = useState("detect")
    const [targetCountry, setTargetCountry] = useState("English (US)")
    const [targetCountryCode, setTargetCountryCode] = useState("en-US")

    const [sourceInput, setSourceInput] = useState("")
    const [targetInput, setTargetInput] = useState("")
    const [copied, setCopied] = useState(false)
    const [loading, setLoading] = useState(false)
    const [imageBase64, setImageBase64] = useState<string | null>(null)

    useEffect(() => {
      const handlePaste = async (e: ClipboardEvent) => {
        const items = e.clipboardData?.items
        if (!items) return

        for (const item of items) {
          if (item.type.startsWith('image/')) {
            const file = item.getAsFile()
            if (file) {
              const reader = new FileReader()
              reader.onload = () => {
                const dataUrl = reader.result as string
                const base64 = dataUrl.split(',')[1] // Strip "data:image/png;base64,"
                setImageBase64(base64)
                setSourceInput((prev) => prev + '[Image attached]')
              }
              reader.readAsDataURL(file)
            }
            break
          }
        }
      }

      document.addEventListener('paste', handlePaste)
      return () => document.removeEventListener('paste', handlePaste)
    }, [])

    const handleTranslate = async () => {
      if (!sourceInput && !imageBase64) return
      setLoading(true)
      try {
        const res = await fetch('/api/translate', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            text: sourceInput.replace('[Image attached]', ''),
            sourceLang: sourceCountry,
            sourceCode: sourceCountryCode,
            targetLang: targetCountry,
            targetCode: targetCountryCode,
            image: imageBase64,
          }),
        })
        const data = await res.json()
        setTargetInput(data.translation || data.error || 'Translation failed')
      } catch {
        setTargetInput('Translation failed')
      } finally {
        setLoading(false)
      }
    }

    const clearAll = () => {
      setSourceInput("")
      setImageBase64(null)
    }
  return (
    <div className="flex flex-col flex-1 items-center bg-sky-50 opacity-70 font-sans dark:bg-black gap-y-5 p-4 md:px-8">
      <div className="flex flex-row items-center justify-center">
          <CountrySelect value={sourceCountry} onChange={setSourceCountry}
                         className={"!h-12 border-b rounded-2xl bg-blue-200 w-full"}
                        showDetect={true} onChangeCode={setSourceCountryCode}/>
          <CountrySelect value={targetCountryCode} onChange={setTargetCountry}
                         className={"!h-12 border-b rounded-2xl bg-blue-200 w-full"}
                        showDetect={false} onChangeCode={setTargetCountryCode}/>

      </div>
      <div className="flex flex-row gap-4 w-full h-full">
        <div className="relative flex-1">
          <Textarea id="text-area"
                    placeholder="Enter text to translate..."
                    className="bg-white border-2 min-h-[300px] md:min-h-[400px] h-full pr-10 !text-lg resize-none"
                    value={sourceInput}
                    onChange={(e) => setSourceInput(e.target.value)}
                    disabled={loading || imageBase64 != null }/>
          {(sourceInput || imageBase64) && (
            <button
              onClick={clearAll}
              className="absolute top-3 right-3 p-1 hover:bg-gray-200 rounded flex items-center gap-1"
            >
              {imageBase64 && <ImageIcon className="w-4 h-4 text-green-500" />}
              <X className="w-4 h-4 text-gray-500" />
            </button>
          )}
        </div>
        <div className="relative flex-1">
          <Textarea id="result-area"
                    placeholder="Translation..."
                    className="bg-blue-200 !text-lg text-blue-800 border-2 min-h-[300px] md:min-h-[400px] h-full pr-10 placeholder:text-blue-800 resize-none"
                    value={targetInput}
                    readOnly />
          {targetInput && (
            <button
              onClick={() => {
                navigator.clipboard.writeText(targetInput)
                setCopied(true)
                setTimeout(() => setCopied(false), 2000)
              }}
              className="absolute top-3 right-3 p-1 hover:bg-blue-300 rounded"
            >
              {copied ? <Check className="w-4 h-4 text-green-600" /> : <Copy className="w-4 h-4 text-blue-800" />}
            </button>
          )}
        </div>
      </div>
        <button
            onClick={handleTranslate}
            disabled={loading || (!sourceInput && !imageBase64)}
            className="bg-blue-600 text-white px-6 py-2 rounded-xl hover:bg-blue-700 disabled:opacity-50"
        >
            {loading ? 'Translating...' : 'Translate'}
        </button>

    </div>
  );
}
