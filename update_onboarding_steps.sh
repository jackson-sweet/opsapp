#!/bin/bash

# Update OrganizationJoinView
cat > /tmp/organization_join_patch.txt << 'EOF'
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 2
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 7 }
        return OnboardingStep.totalSteps(for: userType)
    }
EOF

# Update CompanyCodeInputView
cat > /tmp/company_code_patch.txt << 'EOF'
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 4
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 7 }
        return OnboardingStep.totalSteps(for: userType)
    }
EOF

# Update FieldSetupView
cat > /tmp/field_setup_patch.txt << 'EOF'
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 6
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 7 }
        return OnboardingStep.totalSteps(for: userType)
    }
EOF

# Update PermissionsView
cat > /tmp/permissions_patch.txt << 'EOF'
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 5
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 7 }
        return OnboardingStep.totalSteps(for: userType)
    }
EOF

# Update CompanyBasicInfoView
cat > /tmp/company_basic_patch.txt << 'EOF'
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 3
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 12 }
        return OnboardingStep.totalSteps(for: userType)
    }
EOF

# Update CompanyAddressView
cat > /tmp/company_address_patch.txt << 'EOF'
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 4
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 12 }
        return OnboardingStep.totalSteps(for: userType)
    }
EOF

# Update CompanyContactView
cat > /tmp/company_contact_patch.txt << 'EOF'
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 5
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 12 }
        return OnboardingStep.totalSteps(for: userType)
    }
EOF

# Update CompanyDetailsView
cat > /tmp/company_details_patch.txt << 'EOF'
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 6
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 12 }
        return OnboardingStep.totalSteps(for: userType)
    }
EOF

# Update CompanyCodeDisplayView
cat > /tmp/company_code_display_patch.txt << 'EOF'
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 7
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 12 }
        return OnboardingStep.totalSteps(for: userType)
    }
EOF

# Update TeamInvitesView
cat > /tmp/team_invites_patch.txt << 'EOF'
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 8
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 12 }
        return OnboardingStep.totalSteps(for: userType)
    }
EOF

echo "Step indicator updates prepared"