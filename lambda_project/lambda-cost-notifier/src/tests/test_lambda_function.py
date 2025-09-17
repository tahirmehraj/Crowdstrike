import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))


def test_format_email_with_data():
    """Test email formatting with realistic cost data"""
    from lambda_function import format_email

    data = {
        'ResultsByTime': [{
            'TimePeriod': {'Start': '2024-09-16'},
            'Total': {'BlendedCost': {'Amount': '123.45'}},
            'Groups': [
                {'Keys': ['Amazon S3'], 'Metrics': {'BlendedCost': {'Amount': '50.00'}}},
                {'Keys': ['Amazon EC2'], 'Metrics': {'BlendedCost': {'Amount': '73.45'}}}
            ]
        }]
    }

    result = format_email(data)

    # Verify subject line
    assert result['subject'] == 'AWS Daily Cost Report - $123.45'

    # Verify content has key information
    assert 'Total Cost: $123.45' in result['text']
    assert 'Amazon S3' in result['text']
    assert '$50.00' in result['text']


def test_format_email_no_data():
    """Test email formatting handles empty data gracefully"""
    from lambda_function import format_email

    result = format_email({'ResultsByTime': []})

    # Should handle empty data without crashing
    assert 'No cost data available' in result['text']
    assert 'No cost data available' in result['html']