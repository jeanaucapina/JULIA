import pdfplumber
import os

pdf_path = r'C:/Users/jeanj/Documents/GitHub/JULIA/Proyecto_Unidad1/Proyecto-Unidad1.pdf'
md_path = r'C:/Users/jeanj/Documents/GitHub/JULIA/Proyecto_Unidad1/Proyecto-Unidad1.md'

def extract_pdf_to_md(pdf_path, md_path):
    with pdfplumber.open(pdf_path) as pdf:
        with open(md_path, 'w', encoding='utf-8') as md_file:
            for page in pdf.pages:
                text = page.extract_text()
                if text:
                    md_file.write(text + '\n\n')
                # Extract tables
                tables = page.extract_tables()
                for table in tables:
                    md_file.write('\n')
                    for row in table:
                        md_file.write('| ' + ' | '.join(row) + ' |\n')
                    md_file.write('\n')
extract_pdf_to_md(pdf_path, md_path)
print('PDF extraction to Markdown complete.')
