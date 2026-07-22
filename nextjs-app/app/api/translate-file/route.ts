import { NextRequest, NextResponse } from "next/server";
import { Buffer } from "buffer"; // Explicitly import to fix type conflicts
import axios from "axios";
import PizZip from "pizzip";
import { DOMParser, XMLSerializer } from "@xmldom/xmldom";
import ExcelJS from "exceljs";
import { PDFDocument, StandardFonts, rgb } from "pdf-lib";

// pdf-parse doesn't have a default export in some environments
// This is the most reliable way to import it in Next.js
import * as pdfParse from "pdf-parse";
const pdf = (pdfParse as any).default || pdfParse;

export const maxDuration = 300; // Extend timeout for local LLM processing

/**
 * Helper: Call local Ollama Gemma
 */
async function translateWithGemma(
  text: string,
  targetLang: string,
): Promise<string> {
  if (!text || !text.trim()) return text;
  try {
    const url = `${process.env.OLLAMA_URL || 'http://localhost:11434'}/api/generate`;
    const response = await axios.post(url, {
      model: "translategemma:4b",
      prompt: `Translate this text into ${targetLang}. Return ONLY the translated text without quotes or explanations.\n\nText: ${text}`,
      stream: false,
    });
    return response.data.response.trim();
  } catch (error) {
    console.error("Ollama translation error:", error);
    return text;
  }
}

export async function POST(req: NextRequest) {
  try {
    const formData = await req.formData();
    const file = formData.get("file") as File;
    const targetLang = (formData.get("targetLang") as string) || "Indonesian";

    if (!file) {
      return NextResponse.json({ error: "No file uploaded" }, { status: 400 });
    }

    const arrayBuffer = await file.arrayBuffer();
    // Use 'as any' to avoid the Buffer<ArrayBufferLike> vs Node's Buffer error
    const inputBuffer = Buffer.from(arrayBuffer) as any;
    const extension = file.name.split(".").pop()?.toLowerCase();

    let outputBuffer: Buffer;
    let mimeType: string;

    switch (extension) {
      case "docx":
        outputBuffer = await processDocx(inputBuffer, targetLang);
        mimeType =
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
        break;
      case "pptx":
        outputBuffer = await processPptx(inputBuffer, targetLang);
        mimeType =
          "application/vnd.openxmlformats-officedocument.presentationml.presentation";
        break;
      case "xlsx":
        outputBuffer = await processXlsx(inputBuffer, targetLang);
        mimeType =
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
        break;
      case "pdf":
        outputBuffer = await processPdf(inputBuffer, targetLang);
        mimeType = "application/pdf";
        break;
      default:
        return NextResponse.json(
          { error: "Unsupported file format" },
          { status: 400 },
        );
    }
    const translatedFilename = await translateWithGemma(file.name, targetLang);
    const baseName = file.name.split(".").pop()?.toLowerCase() || "file";
    const fallbackName = `translated_${baseName}.${extension}`;
    return new NextResponse(new Uint8Array(outputBuffer), {
      headers: {
        "Content-Type": mimeType,
        "Content-Disposition": `attachment; filename="translated_${fallbackName}"; filename*=UTF-8''${encodeURIComponent(translatedFilename)}`,
      },
    });
  } catch (error: any) {
    console.error("API Route Error:", error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

/**
 * Word Processing (Maintains Layout via XML manipulation)
 */
async function processDocx(buffer: any, lang: string): Promise<Buffer> {
  const zip = new PizZip(buffer);
  const xmlString = zip.file("word/document.xml")?.asText() || "";
  const doc = new DOMParser().parseFromString(xmlString, "text/xml");
  const nodes = doc.getElementsByTagName("w:t");

  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i];
    if (node.textContent?.trim()) {
      node.textContent = await translateWithGemma(node.textContent, lang);
    }
  }

  zip.file("word/document.xml", new XMLSerializer().serializeToString(doc));
  return zip.generate({ type: "nodebuffer" }) as Buffer;
}

/**
 * PowerPoint Processing (Maintains Shapes via XML manipulation)
 */
async function processPptx(buffer: any, lang: string): Promise<Buffer> {
  const zip = new PizZip(buffer);
  const slideFiles = Object.keys(zip.files).filter((name) =>
    name.startsWith("ppt/slides/slide"),
  );

  for (const file of slideFiles) {
    const xml = zip.file(file)?.asText() || "";
    const doc = new DOMParser().parseFromString(xml, "text/xml");
    const nodes = doc.getElementsByTagName("a:t");

    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      if (node.textContent?.trim()) {
        node.textContent = await translateWithGemma(node.textContent, lang);
      }
    }
    zip.file(file, new XMLSerializer().serializeToString(doc));
  }
  return zip.generate({ type: "nodebuffer" }) as Buffer;
}

/**
 * Excel Processing (Corrected Cell Iteration)
 */
async function processXlsx(buffer: any, lang: string): Promise<Buffer> {
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(buffer);

  for (const sheet of workbook.worksheets) {
    // Collect rows to use for...of loop for async handling
    const rows: ExcelJS.Row[] = [];
    sheet.eachRow({ includeEmpty: false }, (row) => rows.push(row));

    for (const row of rows) {
      const cells: ExcelJS.Cell[] = [];
      row.eachCell({ includeEmpty: false }, (cell) => cells.push(cell));

      for (const cell of cells) {
        if (cell.type === ExcelJS.ValueType.String && cell.value) {
          const originalValue = cell.value.toString();
          cell.value = await translateWithGemma(originalValue, lang);
        }
      }
    }
  }
  const out = await workbook.xlsx.writeBuffer();
  return Buffer.from(out);
}

/**
 * PDF Processing (Basic Text Reconstruction)
 */
async function processPdf(buffer: any, lang: string): Promise<Buffer> {
  const data = await pdf(buffer);
  const translated = await translateWithGemma(data.text, lang);

  const pdfDoc = await PDFDocument.create();
  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const page = pdfDoc.addPage();
  const { width, height } = page.getSize();

  page.drawText(translated, {
    x: 50,
    y: height - 50,
    size: 11,
    font,
    color: rgb(0, 0, 0),
    maxWidth: width - 100,
    lineHeight: 14,
  });

  const bytes = await pdfDoc.save();
  return Buffer.from(bytes);
}
