// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/wheel_date_picker.dart';
import '../../../widgets/auth_widgets.dart';
import '../../../data/registration_draft.dart';
import '../../../utils/step_navigator.dart';
import 'mechanic_step4_documents.dart';

class MechanicStep3IdDetails extends StatefulWidget {
  const MechanicStep3IdDetails({super.key});

  @override
  State<MechanicStep3IdDetails> createState() =>
      _MechanicStep3IdDetailsState();
}

class _MechanicStep3IdDetailsState extends State<MechanicStep3IdDetails> {
  final _draft = RegistrationDraft.instance;

  String? _selectedIdType;
  String _sex = 'Male';

  final _idNumberCtrl      = TextEditingController();
  final _lastNameCtrl      = TextEditingController();
  final _givenNameCtrl     = TextEditingController();
  final _middleNameCtrl    = TextEditingController();
  final _maritalStatusCtrl = TextEditingController();
  final _placeOfBirthCtrl  = TextEditingController(); // optional
  final _dobCtrl           = TextEditingController();
  final _addressCtrl       = TextEditingController();

  DateTime? _selectedDob;
  bool _loaded = false;

  String? _idTypeError;
  String? _idNumberError;
  String? _lastNameError;
  String? _givenNameError;
  String? _middleNameError;
  String? _maritalStatusError;
  String? _dobError;
  String? _addressError;
  List<String> _mismatchErrors = [];

  final List<String> _idTypes = [
    "Passport",
    "Driver's License",
    "SSS ID",
    "PhilHealth ID",
    "Voter's ID",
    "Postal ID",
    "National ID",
  ];

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  void _loadDraft() {
    setState(() {
      _selectedIdType          = _draft.idType.isNotEmpty ? _draft.idType : null;
      _idNumberCtrl.text       = _draft.idNumber;
      _lastNameCtrl.text       = _draft.idLastName;
      _givenNameCtrl.text      = _draft.idGivenName;
      _middleNameCtrl.text     = _draft.idMiddleName;
      _maritalStatusCtrl.text  = _draft.maritalStatus;
      _placeOfBirthCtrl.text   = _draft.placeOfBirth;
      _dobCtrl.text            = _draft.idDob;
      _sex                     = _draft.idSex.isNotEmpty ? _draft.idSex : 'Male';
      _addressCtrl.text        = _draft.idAddress;
      if (_draft.idDob.isNotEmpty) {
        _selectedDob = _parseTypedDate(_draft.idDob);
      }
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _idNumberCtrl.dispose();
    _lastNameCtrl.dispose();
    _givenNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _maritalStatusCtrl.dispose();
    _placeOfBirthCtrl.dispose();
    _dobCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _autosave() {
    _draft.idType        = _selectedIdType ?? '';
    _draft.idNumber      = _idNumberCtrl.text;
    _draft.idLastName    = _lastNameCtrl.text;
    _draft.idGivenName   = _givenNameCtrl.text;
    _draft.idMiddleName  = _middleNameCtrl.text;
    _draft.maritalStatus = _maritalStatusCtrl.text;
    _draft.placeOfBirth  = _placeOfBirthCtrl.text;
    _draft.idDob         = _dobCtrl.text;
    _draft.idSex         = _sex;
    _draft.idAddress     = _addressCtrl.text;
    _draft.saveStep3();
  }

  Future<void> _openCalendar() async {
    final now = DateTime.now();
    final picked = await showWheelDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      title: 'Select Date of Birth',
    );
    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _dobCtrl.text =
            '${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}';
        _dobError = null;
      });
      _autosave();
    }
  }

  DateTime? _parseTypedDate(String text) {
    final parts = text.trim().split('/');
    if (parts.length != 3) return null;
    final month = int.tryParse(parts[0]);
    final day   = int.tryParse(parts[1]);
    final year  = int.tryParse(parts[2]);
    if (month == null || day == null || year == null) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    if (year < 1900 || year > DateTime.now().year) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  String _norm(String s) => s.trim().toLowerCase();

  bool _sameDob(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _validate() {
    String? idTypeErr, idNumErr, lnErr, gnErr, mnErr, maritalErr, dobErr, addrErr;

    if (_selectedIdType == null)              idTypeErr  = 'Please select a type of ID';
    if (_idNumberCtrl.text.trim().isEmpty)    idNumErr   = 'ID number is required';
    if (_lastNameCtrl.text.trim().isEmpty)    lnErr      = 'Last name is required';
    if (_givenNameCtrl.text.trim().isEmpty)   gnErr      = 'Given name is required';
    if (_middleNameCtrl.text.trim().isEmpty)  mnErr      = 'Middle name is required';
    if (_maritalStatusCtrl.text.trim().isEmpty) maritalErr = 'Marital status is required';
    if (_addressCtrl.text.trim().isEmpty)     addrErr    = 'Address is required';

    if (_selectedDob == null) {
      final typed = _parseTypedDate(_dobCtrl.text);
      if (typed == null) {
        dobErr = 'Enter a valid date (mm/dd/yyyy)';
      } else {
        _selectedDob = typed;
      }
    }

    // ── Cross-validation against Step 2 draft ────────────────────────────
    final List<String> mismatches = [];
    if (lnErr == null && gnErr == null && mnErr == null && dobErr == null) {
      if (_norm(_lastNameCtrl.text) != _norm(_draft.lastName)) {
        mismatches.add(
            'Last name does not match personal info ("${_draft.lastName}").');
      }
      if (_norm(_givenNameCtrl.text) != _norm(_draft.firstName)) {
        mismatches.add(
            'Given name does not match personal info ("${_draft.firstName}").');
      }
      if (_norm(_middleNameCtrl.text) != _norm(_draft.middleName)) {
        mismatches.add(
            'Middle name does not match personal info ("${_draft.middleName}").');
      }
      if (_sex != _draft.sex) {
        mismatches.add('Sex does not match personal info ("${_draft.sex}").');
      }
      final step2Dob = _parseTypedDate(_draft.dob);
      if (_selectedDob != null && step2Dob != null &&
          !_sameDob(_selectedDob!, step2Dob)) {
        mismatches.add('Date of birth does not match personal info (${_draft.dob}).');
      }
    }

    setState(() {
      _idTypeError        = idTypeErr;
      _idNumberError      = idNumErr;
      _lastNameError      = lnErr;
      _givenNameError     = gnErr;
      _middleNameError    = mnErr;
      _maritalStatusError = maritalErr;
      _dobError           = dobErr;
      _addressError       = addrErr;
      _mismatchErrors     = mismatches;
    });

    return idTypeErr == null && idNumErr == null && lnErr == null &&
           gnErr == null && mnErr == null && maritalErr == null &&
           dobErr == null && addrErr == null && mismatches.isEmpty;
  }

  Widget _field({required Widget child, required String? error}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error,
                style: TextStyle(fontSize: 11, color: AppColors.error)),
          ),
      ],
    );
  }

  void _onStepTapped(int step) => goToRegistrationStep(context, step);

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const _RegHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: context.layout.pageInsets,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RegistrationStepper(
                    currentStep: 3,
                    highestCompletedStep: _draft.highestCompletedStep,
                    onStepTapped: _onStepTapped,
                  ),
                  const SizedBox(height: 8),
                  Text('Valid ID Details',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.textdark.withValues(alpha: 0.55))),
                  Text(
                    'Please enter the details exactly as they appear on your ID',
                    style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 16),

                  // Mismatch alert
                  if (_mismatchErrors.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ID details must match your personal information:',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.error),
                          ),
                          const SizedBox(height: 6),
                          ..._mismatchErrors.map((e) => Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('• ',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.error)),
                                    Expanded(
                                      child: Text(e,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.error)),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),

                  // Type of ID
                  const Text('Type of ID',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _selectedIdType,
                        hint: const Text('Type of ID'),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: _idTypeError != null
                                  ? AppColors.error
                                  : AppColors.textdark.withValues(alpha: 0.2),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: _idTypeError != null
                                  ? AppColors.error
                                  : AppColors.textdark.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                        items: _idTypes
                            .map((t) => DropdownMenuItem(
                                value: t, child: Text(t)))
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedIdType = v;
                            _idTypeError = null;
                          });
                          _autosave();
                        },
                      ),
                      if (_idTypeError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_idTypeError!,
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.error)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  _field(
                    error: _idNumberError,
                    child: OnGoTextField(
                      label: 'ID Number',
                      hint: '00-000-0000',
                      controller: _idNumberCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) {
                        _autosave();
                        if (_idNumberError != null) {
                          setState(() => _idNumberError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  _field(
                    error: _lastNameError,
                    child: OnGoTextField(
                      label: 'Last Name',
                      hint: 'Cruz',
                      controller: _lastNameCtrl,
                      onChanged: (_) {
                        _autosave();
                        if (_lastNameError != null) {
                          setState(() => _lastNameError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  _field(
                    error: _givenNameError,
                    child: OnGoTextField(
                      label: 'Given Name',
                      hint: 'Juan',
                      controller: _givenNameCtrl,
                      onChanged: (_) {
                        _autosave();
                        if (_givenNameError != null) {
                          setState(() => _givenNameError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  _field(
                    error: _middleNameError,
                    child: OnGoTextField(
                      label: 'Middle Name',
                      hint: 'Dela',
                      controller: _middleNameCtrl,
                      onChanged: (_) {
                        _autosave();
                        if (_middleNameError != null) {
                          setState(() => _middleNameError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  _field(
                    error: _maritalStatusError,
                    child: OnGoTextField(
                      label: 'Marital Status',
                      hint: 'Single',
                      controller: _maritalStatusCtrl,
                      onChanged: (_) {
                        _autosave();
                        if (_maritalStatusError != null) {
                          setState(() => _maritalStatusError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Place of Birth — optional
                  OnGoTextField(
                    label: 'Place of Birth (Optional)',
                    hint: 'Puerto Princesa City',
                    controller: _placeOfBirthCtrl,
                    onChanged: (_) => _autosave(),
                  ),
                  const SizedBox(height: 14),

                  // Date of Birth — type or pick
                  _field(
                    error: _dobError,
                    child: OnGoTextField(
                      label: 'Date of Birth',
                      hint: 'mm/dd/yyyy',
                      controller: _dobCtrl,
                      keyboardType: TextInputType.datetime,
                      onChanged: (_) {
                        _selectedDob = null;
                        _autosave();
                        if (_dobError != null) setState(() => _dobError = null);
                      },
                      suffixIcon: GestureDetector(
                        onTap: _openCalendar,
                        child: Icon(Icons.calendar_today_outlined,
                            size: 18, color: AppColors.textdark.withValues(alpha: 0.55)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Sex
                  const Text('Sex',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Row(
                    children: ['Male', 'Female'].map((s) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<String>(
                            value: s,
                            groupValue: _sex,
                            activeColor: AppColors.primary,
                            onChanged: (v) {
                              setState(() => _sex = v ?? 'Male');
                              _autosave();
                            },
                          ),
                          Text(s, style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 8),
                        ],
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  _field(
                    error: _addressError,
                    child: OnGoTextField(
                      label: 'Address',
                      hint: 'Puerto Princesa',
                      controller: _addressCtrl,
                      onChanged: (_) {
                        _autosave();
                        if (_addressError != null) {
                          setState(() => _addressError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 28),

                  StepNavButtons(
                    onBack: () => Navigator.pop(context),
                    onNext: () {
                      if (!_validate()) return;
                      _draft.idType        = _selectedIdType!;
                      _draft.idNumber      = _idNumberCtrl.text.trim();
                      _draft.idLastName    = _lastNameCtrl.text.trim();
                      _draft.idGivenName   = _givenNameCtrl.text.trim();
                      _draft.idMiddleName  = _middleNameCtrl.text.trim();
                      _draft.maritalStatus = _maritalStatusCtrl.text.trim();
                      _draft.placeOfBirth  = _placeOfBirthCtrl.text.trim();
                      _draft.idDob         = _dobCtrl.text;
                      _draft.idSex         = _sex;
                      _draft.idAddress     = _addressCtrl.text.trim();
                      _draft.saveStep3();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const MechanicStep4Documents()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegHeader extends StatelessWidget {
  const _RegHeader();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
      child: Column(
        children: [
          Text('On Go Registration',
              style: TextStyle(
                  color: AppColors.textlight,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text('Complete all steps to provide services',
              style: TextStyle(color: AppColors.textlight, fontSize: 12)),
        ],
      ),
    );
  }
}