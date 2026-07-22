'use client';

import React, { useState, useRef } from 'react';

export default function DocumentTranslator() {
    const [file, setFile] = useState<File | null>(null);
    const [language, setLanguage] = useState('Indonesian');
    const [isTranslating, setIsTranslating] = useState(false);
    const [status, setStatus] = useState<{ message: string; type: 'info' | 'error' | 'success' | '' }>({
        message: '',
        type: '',
    });

    const fileInputRef = useRef<HTMLInputElement>(null);

    const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        if (e.target.files && e.target.files[0]) {
            setFile(e.target.files[0]);
            setStatus({ message: '', type: '' });
        }
    };

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!file) return;

        setIsTranslating(true);
        setStatus({ message: 'Ollama is processing your translation... Please wait.', type: 'info' });

        const formData = new FormData();
        formData.append('file', file);
        formData.append('targetLang', language);

        try {
            const response = await fetch('/api/translate-file', {
                method: 'POST',
                body: formData,
            });

            if (!response.ok) throw new Error('Translation failed');

            const blob = await response.blob();
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `translated_${file.name}`;
            document.body.appendChild(a);
            a.click();

            window.URL.revokeObjectURL(url);
            document.body.removeChild(a);

            setStatus({ message: 'Success! Your file has been downloaded.', type: 'success' });
        } catch (err) {
            setStatus({ message: 'Error: Connection to Ollama failed or file is unsupported.', type: 'error' });
        } finally {
            setIsTranslating(false);
        }
    };

    return (
        <div className="min-h-screen bg-slate-50 flex items-center justify-center p-4">
            <div className="w-full max-w-xl bg-white rounded-3xl shadow-xl overflow-hidden border border-slate-200">

                {/* Header */}
                <div className="bg-blue-600 p-8 text-white text-center">
                    <h1 className="text-3xl font-bold">Gemma Doc Translator</h1>
                    <p className="text-blue-100 mt-2">Translate Word, PPT, Excel, and PDF locally</p>
                </div>

                {/* Form Area */}
                <form onSubmit={handleSubmit} className="p-8 space-y-6">

                    {/* Custom Upload Box */}
                    <div
                        onClick={() => fileInputRef.current?.click()}
                        className={`border-2 border-dashed rounded-2xl p-8 text-center cursor-pointer transition-all
              ${file ? 'border-blue-400 bg-blue-50' : 'border-slate-300 hover:border-blue-400 hover:bg-slate-50'}`}
                    >
                        <input
                            type="file"
                            ref={fileInputRef}
                            onChange={handleFileChange}
                            className="hidden"
                            accept=".docx,.pptx,.xlsx,.pdf"
                        />

                        <div className="flex flex-col items-center">
                            <span className="text-4xl mb-3">{file ? '📄' : '📁'}</span>
                            {file ? (
                                <div>
                                    <p className="font-semibold text-slate-800">{file.name}</p>
                                    <p className="text-xs text-slate-500">{(file.size / 1024).toFixed(1)} KB</p>
                                </div>
                            ) : (
                                <div>
                                    <p className="font-semibold text-slate-700">Click to upload or drag and drop</p>
                                    <p className="text-xs text-slate-400">DOCX, PPTX, XLSX, or PDF</p>
                                </div>
                            )}
                        </div>
                    </div>

                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        {/* Language Selector */}
                        <div className="space-y-1">
                            <label className="text-xs font-bold text-slate-500 uppercase tracking-wider">Target Language</label>
                            <select
                                value={language}
                                onChange={(e) => setLanguage(e.target.value)}
                                className="w-full bg-slate-100 border-none rounded-xl p-3 focus:ring-2 focus:ring-blue-500 outline-none font-medium text-slate-700"
                            >
                                <option value="Indonesian">Indonesian</option>
                                <option value="Japanese">Japanese</option>
                                <option value="Spanish">Spanish</option>
                                <option value="German">German</option>
                                <option value="French">French</option>
                            </select>
                        </div>

                        {/* Submit Button */}
                        <div className="flex items-end">
                            <button
                                type="submit"
                                disabled={!file || isTranslating}
                                className={`w-full p-3 rounded-xl font-bold text-white transition-all shadow-lg
                  ${!file || isTranslating
                                    ? 'bg-slate-300 cursor-not-allowed shadow-none'
                                    : 'bg-blue-600 hover:bg-blue-700 active:scale-95'}`}
                            >
                                {isTranslating ? (
                                    <span className="flex items-center justify-center gap-2">
                    <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></span>
                    Processing...
                  </span>
                                ) : 'Download Translation'}
                            </button>
                        </div>
                    </div>
                </form>

                {/* Status Message Footer */}
                {status.message && (
                    <div className={`px-8 py-4 text-sm text-center font-medium border-t
            ${status.type === 'error' ? 'bg-red-50 text-red-600 border-red-100' :
                        status.type === 'success' ? 'bg-emerald-50 text-emerald-600 border-emerald-100' :
                            'bg-blue-50 text-blue-600 border-blue-100'}`}>
                        {status.message}
                    </div>
                )}
            </div>
        </div>
    );
}