module FactoryGirl
  # Allow re-registering of sequences with new code blocks, but without resetting the sequence numbers;
  # if the sequence numbers reset, then they'd overlap with the fixtures that are created pre-fork above
  def self.register_sequence(sequence)
    begin
      sequences.add(sequence)
    rescue FactoryGirl::DuplicateDefinitionError
      sequences[sequence.name].instance_eval do
        @proc = sequence.instance_eval { @proc }
      end
    end
  end
end
