package com.ragpeat.chat;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class PersonalDataTest {

    // Datos inventados, con la forma de una analítica pegada tal cual.
    private static final String LAB_REPORT = """
            DNI: 31415926
            Fecha Toma Muestra
            07/09/2026
            HC: 2718281
            Fecha Nac.: 01/02/1990
            Médico: GARCIA LOPEZ ANA
            Nro. Informe:1/1
            110622330100
            174 COLESTEROL TOTAL 759 PROLACTINA PLASMATICA
            Colesterol total: 215 mg/dl
            TSH: 3,2 uUI/ml""";

    @Test
    void removesIdentifiersFromPastedLabReport() {
        String redacted = PersonalData.redact(LAB_REPORT);

        assertThat(redacted).doesNotContain("31415926", "2718281", "01/02/1990", "GARCIA", "110622330100");
        assertThat(redacted).contains("DNI: [dato personal]", "Fecha Nac.: [dato personal]", "Médico: [dato personal]");
    }

    @Test
    void keepsTheLabResults() {
        String redacted = PersonalData.redact(LAB_REPORT);

        assertThat(redacted).contains("Colesterol total: 215 mg/dl", "TSH: 3,2 uUI/ml",
                "174 COLESTEROL TOTAL 759 PROLACTINA PLASMATICA", "07/09/2026");
    }

    @Test
    void splitsTwoLabelsOnTheSameLine() {
        assertThat(PersonalData.redact("HC: 2718281 Fecha Nac.: 01/02/1990"))
                .isEqualTo("HC: [dato personal] Fecha Nac.: [dato personal]");
    }

    @Test
    void removesUnlabeledIdentifiers() {
        assertThat(PersonalData.redact("mi email es ana.g@example.com y mi DNI 12345678Z, llamadme al +34 600 123 456"))
                .doesNotContain("ana.g@example.com", "12345678Z", "600 123 456");
    }

    @Test
    void leavesBotAnswersAlone() {
        String answer = """
                - **Energía celular:** Según él, la serotonina «lowers cellular ATP» [1].
                - **Médico:** no lo sustituye.
                El papel del médico: acompañar. Tu edad: no importa.""";
        assertThat(PersonalData.redact(answer)).isEqualTo(answer);
    }

    @Test
    void weakLabelsCountAtTheStartOfALine() {
        assertThat(PersonalData.redact("Paciente: PEREZ JUAN\nTel: 600123456"))
                .isEqualTo("Paciente: [dato personal]\nTel: [dato personal]");
    }

    @Test
    void handlesHospitalReportFormats() {
        // Datos inventados, con el formato de un informe real que se coló.
        String report = """
                Fecha de nacimiento (edad): 01/02/1990 (36 años)
                Hemoglobina: 16.6 g/dl (13 - 17)
                Responsable Análisis Clínicos: Ana Prueba Garcia
                Dirección técnica: Luis Prueba Perez
                Facultativo responsable: Dra. Prueba""";
        String redacted = PersonalData.redact(report);
        assertThat(redacted).doesNotContain("1990", "Ana Prueba", "Luis Prueba", "Dra. Prueba");
        assertThat(redacted).contains("Hemoglobina: 16.6 g/dl (13 - 17)", "Fecha de nacimiento (edad): [dato personal]");
    }

    @Test
    void handlesEnglishLabReports() {
        // Datos inventados, con la forma de una analítica de EE. UU.
        String report = """
                Patient Name: SMITH, JOHN A
                DOB: 01/02/1980    Age: 46
                MRN: 00123456
                Ordering Physician: Jane Doe, MD
                Phone: (555) 123-4567
                Accession #: AB12-3456
                TSH 3.20 uIU/mL 0.45-4.50
                Testosterone, Total: 512 ng/dL""";
        String redacted = PersonalData.redact(report);
        assertThat(redacted).doesNotContain("SMITH", "1980", "00123456", "Jane Doe", "123-4567", "AB12-3456");
        assertThat(redacted).contains("TSH 3.20 uIU/mL 0.45-4.50", "Testosterone, Total: 512 ng/dL",
                "Patient Name: [dato personal]", "DOB: [dato personal]");
    }

    @Test
    void leavesNormalEnglishQuestionsAlone() {
        String question = """
                My doctor says my TSH is 4.5 and my age is 46. What did Peat think about the name "hypothyroid"?
                Patients often ask: is 1.5 to 2 g of aspirin a lot? Range 0.45-4.50, 150-400, 3.5 - 5.0""";
        assertThat(PersonalData.redact(question)).isEqualTo(question);
    }

    @Test
    void handlesOtherLanguagesLabReports() {
        // Datos inventados: una línea típica de informe en portugués, francés, alemán, italiano y turco.
        String report = """
                Nome: MARIA PRUEBA SILVA
                Data de nascimento: 03/04/1985
                CPF: 123.456.789-00
                Nom: DUPONT
                Date de naissance: 05/06/1975
                Geburtsdatum: 07/08/1965
                Arzt: Dr. Prueba Müller
                Codice fiscale: PRBMRA85D43H501X
                Adı Soyadı: AYŞE PRUEBA
                Doğum Tarihi: 09/10/1990
                TSH: 2,1 mU/l
                Ferritin: 85 ng/ml""";
        String redacted = PersonalData.redact(report);
        assertThat(redacted).doesNotContain("MARIA", "1985", "123.456", "DUPONT", "1975", "1965", "Müller",
                "PRBMRA", "AYŞE", "1990");
        assertThat(redacted).contains("TSH: 2,1 mU/l", "Ferritin: 85 ng/ml", "Geburtsdatum: [dato personal]");
    }

    @Test
    void leavesNormalQuestionsInOtherLanguagesAlone() {
        String question = """
                Mein Arzt sagt, mein TSH ist 4,5. Was dachte Peat über Schilddrüse? Alter 46, Gewicht 70 kg.
                O que Peat pensava do açúcar? A minha idade é 40 anos.
                Que pensait Peat du café ? Mon médecin dit que c'est mauvais.
                Doktorum TSH değerim 4,5 dedi. Peat tiroid hakkında ne düşünüyordu?""";
        assertThat(PersonalData.redact(question)).isEqualTo(question);
    }

    @Test
    void leavesNormalQuestionsAlone() {
        String question = "Mi médico me dijo que tengo el LDL en 160 y la TSH en 4,5. ¿Qué pensaba Peat? Peso 52 kg y mido 157 cm.";
        assertThat(PersonalData.redact(question)).isEqualTo(question);
    }
}
