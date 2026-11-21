import 'dart:convert';

import '../recording_engine/template_review.dart';
import 'nursing_pilot.dart';
import 'template_bundle.dart';

String _key(String definition) => nursingPilot.fields
    .singleWhere((field) => field.definition.id == definition)
    .id;

final nursingBundle = ProfessionTemplateBundle.decode(
  encodeSettings({
    'format': 1,
    'minimumReader': 1,
    'recipe': jsonDecode(encodeTemplateDefinition(nursingPilot)),
    'scheme': 'NMC revalidation activity log',
    'profession': 'Nurses, midwives and nursing associates',
    'country': 'United Kingdom',
    'body': 'Nursing and Midwifery Council',
    'reviewed': '2026-11-21',
    'product': 'template.uk.nmc.activity_log',
    'sources': [
      'https://www.nmc.org.uk/revalidation/requirements/cpd/',
      'https://www.nmc.org.uk/revalidation/online-application/revalidation-date/',
    ],
    'rules': {
      'calculator': 'log_minutes_v1',
      'version': 1,
      'inputs': {
        'date': _key('cpd.activityDate'),
        'title': _key('cpd.title'),
        'details': _key('cpd.details'),
        'minutes': _key('cpd.creditedDuration'),
        'participatory': 'nmc.participatory',
        'evidence': _key('cpd.evidence'),
        'method': 'nmc.method',
        'code': 'nmc.code',
        'firstDay': 'nmc.start',
      },
      'required': [
        'date',
        'title',
        'details',
        'minutes',
        'participatory',
        'evidence',
        'method',
        'code',
      ],
      'periods': ['custom', 'fixed', 'rolling'],
      'cycleMonths': 36,
      'metrics': [
        const SchemeMetric('total', ActivityInput.minutes, 35 * 60).toJson(),
        const SchemeMetric(
          'participatory',
          ActivityInput.participatory,
          20 * 60,
        ).toJson(),
      ],
    },
    'tile': {
      'metrics': ['total', 'participatory'],
      'deadline': true,
    },
    'report': {
      'kind': 'activity_log_v1',
      'branding': 'subtle',
      'version': 1,
      'fields': nursingPilot.fields.map((field) => field.id).toList(),
    },
    'preview': {
      'evidence': {'preview.sample': 'Synthetic evidence reference'},
      'examples': [
        for (final example in nursingExamples(nursingPilot))
          {'title': example.label, 'values': example.values},
      ],
    },
    'labels': {
      for (final label in _labels.entries)
        if (label.key.startsWith('cpd.'))
          _key(label.key): label.value
        else
          label.key: label.value,
    },
  }),
);

const _labels = {
  'period': {
    'en': 'Revalidation period',
    'de': 'Revalidierungszeitraum',
    'es': 'Periodo de revalidación',
    'fr': 'Période de revalidation',
    'hi': 'पुनर्सत्यापन अवधि',
    'pt': 'Período de revalidação',
  },
  'scope': {
    'en':
        "Independent CPD log. Confirm eligibility and submit revalidation separately through MyNMC.",
    'de':
        "Unabhängiger Fortbildungsnachweis. Prüfen Sie die Anrechenbarkeit und beantragen Sie die Revalidierung separat in MyNMC.",
    'es':
        "Registro de formación independiente. Confirma qué horas se aceptan y tramita la revalidación por separado en MyNMC.",
    'fr':
        "Journal de formation indépendant. Vérifiez l’admissibilité et faites la demande de revalidation séparément dans MyNMC.",
    'hi':
        "स्वतंत्र सीपीडी रिकॉर्ड। पात्रता जाँचें और पुनर्सत्यापन के लिए MyNMC में अलग से आवेदन करें।",
    'pt':
        "Registo de formação independente. Confirme a elegibilidade e submeta a revalidação separadamente no MyNMC.",
  },
  'periodHint': {
    'en':
        "Use your registration dates and confirm the application deadline in MyNMC.",
    'de':
        "Verwenden Sie Ihre Registrierungsdaten und prüfen Sie die Antragsfrist in MyNMC.",
    'es': "Utiliza tus fechas de registro y comprueba el plazo en MyNMC.",
    'fr':
        "Utilisez vos dates d’inscription et vérifiez la date limite dans MyNMC.",
    'hi':
        "अपने पंजीकरण की तारीखें डालें और MyNMC में आवेदन की अंतिम तारीख जाँचें।",
    'pt': "Use as suas datas de registo e confirme o prazo no MyNMC.",
  },
  'description': {
    'en': 'Record learning for an NMC revalidation activity log.',
    'de': 'Lernaktivitäten für die NMC-Revalidierung erfassen.',
    'es': 'Registra actividades para la revalidación del NMC.',
    'fr': 'Consignez les activités pour la revalidation du NMC.',
    'hi': 'एनएमसी पुनर्सत्यापन के लिए प्रशिक्षण गतिविधियाँ दर्ज करें।',
    'pt': 'Registe atividades para a revalidação do NMC.',
  },
  'report': {
    'en': 'UK nursing and midwifery CPD activity log',
    'de': 'Fortbildungsnachweis für Pflege und Geburtshilfe',
    'es': 'Registro de formación de enfermería y partería',
    'fr': 'Journal de formation infirmière et sage-femme',
    'hi': 'नर्सिंग और दाई सेवा का प्रशिक्षण रिकॉर्ड',
    'pt': 'Registo de formação em enfermagem e obstetrícia',
  },
  'total': {
    'en': 'Total CPD',
    'de': 'Fortbildung gesamt',
    'es': 'Formación total',
    'fr': 'Formation totale',
    'hi': 'कुल सीपीडी',
    'pt': 'Formação total',
  },
  'participatory': {
    'en': 'Participatory learning',
    'de': 'Interaktives Lernen',
    'es': 'Aprendizaje participativo',
    'fr': 'Apprentissage participatif',
    'hi': 'सहभागी प्रशिक्षण',
    'pt': 'Aprendizagem participativa',
  },
  'cpd.activityDate': {
    'de': 'Aktivitätsdatum',
    'es': 'Fecha de la actividad',
    'fr': 'Date de l’activité',
    'hi': 'गतिविधि की तारीख',
    'pt': 'Data da atividade',
  },
  'cpd.title': {
    'de': 'Titel',
    'es': 'Título',
    'fr': 'Titre',
    'hi': 'शीर्षक',
    'pt': 'Título',
  },
  'cpd.details': {
    'de': 'Details',
    'es': 'Detalles',
    'fr': 'Détails',
    'hi': 'विवरण',
    'pt': 'Detalhes',
  },
  'cpd.creditedDuration': {
    'de': 'Fortbildungsdauer',
    'es': 'Duración de la formación',
    'fr': 'Durée de formation',
    'hi': 'सीपीडी अवधि',
    'pt': 'Duração da formação',
  },
  'cpd.evidence': {
    'de': 'Nachweise',
    'es': 'Evidencia',
    'fr': 'Justificatifs',
    'hi': 'साक्ष्य',
    'pt': 'Evidência',
  },
  'nmc.method': {
    'de': 'Lernmethode',
    'es': 'Método de aprendizaje',
    'fr': 'Méthode d’apprentissage',
    'hi': 'सीखने की विधि',
    'pt': 'Método de aprendizagem',
  },
  'nmc.start': {
    'de': 'Erster Tag einer mehrtägigen Aktivität',
    'es': 'Primer día de una actividad de varios días',
    'fr': 'Premier jour d’une activité sur plusieurs jours',
    'hi': 'कई दिनों की गतिविधि का पहला दिन',
    'pt': 'Primeiro dia de uma atividade com vários dias',
  },
  'nmc.participatory': {
    'en': 'Participatory learning',
    'de': 'Interaktives Lernen',
    'es': 'Aprendizaje participativo',
    'fr': 'Apprentissage participatif',
    'hi': 'सहभागी प्रशिक्षण',
    'pt': 'Aprendizagem participativa',
  },
  'nmc.code': {
    'de': 'Relevante Teile des Kodex',
    'es': 'Apartados pertinentes del código',
    'fr': 'Parties pertinentes du code',
    'hi': 'आचार संहिता के प्रासंगिक भाग',
    'pt': 'Partes relevantes do código',
  },
  'nmc.practice': {
    'de': 'Anwendung in der Praxis',
    'es': 'Aplicación en la práctica',
    'fr': 'Mise en pratique',
    'hi': 'अभ्यास में सीख का उपयोग',
    'pt': 'Aplicação na prática',
  },
  'nmc.standards': {
    'de': 'Relevante Kompetenzstandards',
    'es': 'Estándares de competencia pertinentes',
    'fr': 'Normes de compétence pertinentes',
    'hi': 'प्रासंगिक दक्षता मानक',
    'pt': 'Normas de competência relevantes',
  },
};
