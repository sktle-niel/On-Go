// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/wheel_date_picker.dart';
import '../../../widgets/auth_widgets.dart';
import '../../../data/registration_draft.dart';
import '../../../utils/step_navigator.dart';
import 'mechanic_step3_id_details.dart';

class MechanicStep2Personal extends StatefulWidget {
  const MechanicStep2Personal({super.key});

  @override
  State<MechanicStep2Personal> createState() => _MechanicStep2PersonalState();
}

class _MechanicStep2PersonalState extends State<MechanicStep2Personal> {
  final _draft = RegistrationDraft.instance;

  final _firstNameCtrl  = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl   = TextEditingController();
  final _suffixCtrl     = TextEditingController();
  final _dobCtrl        = TextEditingController();
  final _addressCtrl    = TextEditingController();
  final _mobileCtrl     = TextEditingController();

  String _sex = 'Male';
  DateTime? _selectedDob;
  bool _loaded = false;

  String? _firstNameError;
  String? _middleNameError;
  String? _lastNameError;
  String? _dobError;
  String? _addressError;
  String? _mobileError;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  void _loadDraft() {
    // Draft already loaded by Step 1 (or on fresh open); just populate fields.
    setState(() {
      _firstNameCtrl.text  = _draft.firstName;
      _middleNameCtrl.text = _draft.middleName;
      _lastNameCtrl.text   = _draft.lastName;
      _suffixCtrl.text     = _draft.suffix;
      _dobCtrl.text        = _draft.dob;
      _sex                 = _draft.sex.isNotEmpty ? _draft.sex : 'Male';
      _addressCtrl.text    = _draft.address;
      _mobileCtrl.text     = _draft.mobile;
      // Re-parse saved DOB so calendar initial date is correct
      if (_draft.dob.isNotEmpty) {
        _selectedDob = _parseTypedDate(_draft.dob);
      }
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _suffixCtrl.dispose();
    _dobCtrl.dispose();
    _addressCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  void _autosave() {
    _draft.firstName  = _firstNameCtrl.text;
    _draft.middleName = _middleNameCtrl.text;
    _draft.lastName   = _lastNameCtrl.text;
    _draft.suffix     = _suffixCtrl.text;
    _draft.dob        = _dobCtrl.text;
    _draft.sex        = _sex;
    _draft.address    = _addressCtrl.text;
    _draft.mobile     = _mobileCtrl.text;
    _draft.saveStep2();
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

  bool _validate() {
    String? fnErr, mnErr, lnErr, dobErr, addrErr, mobErr;

    if (_firstNameCtrl.text.trim().isEmpty) fnErr  = 'First name is required';
    if (_middleNameCtrl.text.trim().isEmpty) mnErr = 'Middle name is required';
    if (_lastNameCtrl.text.trim().isEmpty)  lnErr  = 'Last name is required';

    if (_selectedDob == null) {
      final typed = _parseTypedDate(_dobCtrl.text);
      if (typed == null) {
        dobErr = 'Enter a valid date (mm/dd/yyyy)';
      } else {
        _selectedDob = typed;
      }
    }

    if (_addressCtrl.text.trim().isEmpty) addrErr = 'Permanent address is required';

    final mob = _mobileCtrl.text.trim();
    if (mob.isEmpty) {
      mobErr = 'Mobile number is required';
    } else if (!RegExp(r'^09\d{9}$').hasMatch(mob)) {
      mobErr = 'Enter a valid PH number (09XXXXXXXXX — 11 digits)';
    }

    setState(() {
      _firstNameError  = fnErr;
      _middleNameError = mnErr;
      _lastNameError   = lnErr;
      _dobError        = dobErr;
      _addressError    = addrErr;
      _mobileError     = mobErr;
    });

    return fnErr == null && mnErr == null && lnErr == null &&
           dobErr == null && addrErr == null && mobErr == null;
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
                    currentStep: 2,
                    highestCompletedStep: _draft.highestCompletedStep,
                    onStepTapped: _onStepTapped,
                  ),
                  const SizedBox(height: 20),
                  Text('Personal Information',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textdark)),
                  const SizedBox(height: 16),

                  // First Name
                  _field(
                    error: _firstNameError,
                    child: OnGoTextField(
                      label: 'First Name',
                      hint: 'Juan',
                      controller: _firstNameCtrl,
                      onChanged: (_) {
                        _autosave();
                        if (_firstNameError != null) {
                          setState(() => _firstNameError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Middle Name — required
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

                  // Last Name
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

                  // Suffix — optional, no validation
                  OnGoTextField(
                    label: 'Suffix (Optional)',
                    hint: 'Jr., Sr., II, III',
                    controller: _suffixCtrl,
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
                        _selectedDob = null; // reset calendar pick on manual type
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

                  // Permanent Address
                  _field(
                    error: _addressError,
                    child: OnGoTextField(
                      label: 'Permanent Address',
                      hint: 'Address',
                      controller: _addressCtrl,
                      onChanged: (_) {
                        _autosave();
                        if (_addressError != null) {
                          setState(() => _addressError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Mobile — PH format
                  _field(
                    error: _mobileError,
                    child: OnGoTextField(
                      label: 'Mobile Number',
                      hint: '09XXXXXXXXX',
                      controller: _mobileCtrl,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) {
                        _autosave();
                        if (_mobileError != null) {
                          setState(() => _mobileError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 28),

                  StepNavButtons(
                    onBack: () => Navigator.pop(context),
                    onNext: () {
                      if (!_validate()) return;
                      // Commit validated values to draft
                      _draft.firstName  = _firstNameCtrl.text.trim();
                      _draft.middleName = _middleNameCtrl.text.trim();
                      _draft.lastName   = _lastNameCtrl.text.trim();
                      _draft.suffix     = _suffixCtrl.text.trim();
                      _draft.dob        = _dobCtrl.text;
                      _draft.sex        = _sex;
                      _draft.address    = _addressCtrl.text.trim();
                      _draft.mobile     = _mobileCtrl.text.trim();
                      _draft.saveStep2();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const MechanicStep3IdDetails()),
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