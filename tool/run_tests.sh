#!/bin/bash

# Test Runner Script for isolate_kit
# Usage: ./tool/run_tests.sh [option]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check Flutter installation
check_flutter() {
    if ! command -v flutter &> /dev/null; then
        print_error "Flutter is not installed!"
        exit 1
    fi
    print_success "Flutter found: $(flutter --version | head -n 1)"
}

# Get dependencies
get_deps() {
    print_header "Getting Dependencies"
    flutter pub get
    print_success "Dependencies installed"
}

# Run all tests
run_all_tests() {
    print_header "Running All Tests"
    flutter test --reporter expanded
    print_success "All tests passed"
}

# Run unit tests only
run_unit_tests() {
    print_header "Running Unit Tests"
    flutter test test/isolate_controller_test.dart --reporter expanded
    flutter test test/transferable_helper_test.dart --reporter expanded
    print_success "Unit tests passed"
}

# Run integration tests only
run_integration_tests() {
    print_header "Running Integration Tests"
    flutter test test/integration_test.dart --reporter expanded
    print_success "Integration tests passed"
}

# Run with coverage
run_with_coverage() {
    print_header "Running Tests with Coverage"
    
    # Clean previous coverage
    rm -rf coverage
    
    # Run tests
    flutter test --coverage --reporter expanded
    
    # Check if lcov is installed
    if command -v lcov &> /dev/null; then
        print_header "Coverage Summary"
        lcov --summary coverage/lcov.info
        
        # Check coverage threshold
        COVERAGE=$(lcov --summary coverage/lcov.info | grep lines | awk '{print $2}' | sed 's/%//')
        echo "Coverage: $COVERAGE%"
        
        if (( $(echo "$COVERAGE < 85" | bc -l) )); then
            print_warning "Coverage is below 85%"
        else
            print_success "Coverage is above 85%"
        fi
        
        # Generate HTML report
        if command -v genhtml &> /dev/null; then
            print_header "Generating HTML Report"
            genhtml coverage/lcov.info -o coverage/html
            print_success "HTML report generated at coverage/html/index.html"
            
            # Open report (macOS/Linux)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                open coverage/html/index.html
            elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                xdg-open coverage/html/index.html 2>/dev/null || true
            fi
        fi
    else
        print_warning "lcov not installed. Install with: brew install lcov (macOS) or apt-get install lcov (Linux)"
    fi
}

# Run stress tests
run_stress_tests() {
    print_header "Running Stress Tests"
    flutter test test/integration_test.dart --name "Stress" --reporter expanded
    print_success "Stress tests passed"
}

# Run specific test
run_specific_test() {
    print_header "Running Specific Test: $1"
    flutter test --name "$1" --reporter expanded
    print_success "Test passed"
}

# Analyze code
analyze_code() {
    print_header "Analyzing Code"
    flutter analyze
    print_success "No issues found"
}

# Format code
format_code() {
    print_header "Formatting Code"
    dart format .
    print_success "Code formatted"
}

# Check formatting
check_format() {
    print_header "Checking Code Format"
    dart format --output=none --set-exit-if-changed .
    print_success "Code is properly formatted"
}

# Pub checks
pub_checks() {
    print_header "Running Pub Checks"
    flutter pub publish --dry-run
    print_success "Package is ready for publishing"
}

# Quick check (format + analyze + tests)
quick_check() {
    print_header "Running Quick Check"
    check_format
    analyze_code
    run_unit_tests
    print_success "Quick check completed"
}

# Full check (format + analyze + all tests + coverage)
full_check() {
    print_header "Running Full Check"
    check_format
    analyze_code
    run_with_coverage
    pub_checks
    print_success "Full check completed"
}

# Watch mode
watch_tests() {
    print_header "Starting Watch Mode"
    print_warning "Press Ctrl+C to stop"
    flutter test --watch
}

# Clean
clean() {
    print_header "Cleaning"
    flutter clean
    rm -rf coverage
    rm -rf .dart_tool
    print_success "Cleaned"
}

# Show help
show_help() {
    echo "Test Runner for isolate_controller"
    echo ""
    echo "Usage: ./tool/run_tests.sh [option]"
    echo ""
    echo "Options:"
    echo "  all              Run all tests (default)"
    echo "  unit             Run unit tests only"
    echo "  integration      Run integration tests only"
    echo "  stress           Run stress tests only"
    echo "  coverage         Run tests with coverage report"
    echo "  analyze          Analyze code"
    echo "  format           Format code"
    echo "  check-format     Check if code is formatted"
    echo "  pub              Run pub checks"
    echo "  quick            Quick check (format + analyze + unit tests)"
    echo "  full             Full check (format + analyze + all tests + coverage)"
    echo "  watch            Run tests in watch mode"
    echo "  clean            Clean build artifacts"
    echo "  specific <name>  Run specific test by name"
    echo "  help             Show this help"
    echo ""
    echo "Examples:"
    echo "  ./tool/run_tests.sh                    # Run all tests"
    echo "  ./tool/run_tests.sh coverage           # Run with coverage"
    echo "  ./tool/run_tests.sh specific \"CancellationToken\"  # Run specific test"
    echo "  ./tool/run_tests.sh quick              # Quick validation"
}

# Main
main() {
    check_flutter
    get_deps
    
    case "${1:-all}" in
        all)
            run_all_tests
            ;;
        unit)
            run_unit_tests
            ;;
        integration)
            run_integration_tests
            ;;
        stress)
            run_stress_tests
            ;;
        coverage)
            run_with_coverage
            ;;
        analyze)
            analyze_code
            ;;
        format)
            format_code
            ;;
        check-format)
            check_format
            ;;
        pub)
            pub_checks
            ;;
        quick)
            quick_check
            ;;
        full)
            full_check
            ;;
        watch)
            watch_tests
            ;;
        clean)
            clean
            ;;
        specific)
            if [ -z "$2" ]; then
                print_error "Please provide test name"
                echo "Usage: ./tool/run_tests.sh specific \"TestName\""
                exit 1
            fi
            run_specific_test "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main
main "$@"