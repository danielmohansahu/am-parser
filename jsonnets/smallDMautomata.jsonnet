#CHECKLIST:

# Tasks?
# Main task?
# Freda?
# Evaluate on test?
# Evaluate on the right test corpora?

local lr = 0.002;
local num_epochs = 400;
local patience = 10000;
local pos_dim = 8;
local lemma_dim = 8;
local word_dim = 64;
local ner_dim = 8;
local hidden_dim = 128;

local eval_commands = import '../configs/eval_commands.libsonnet';

local encoder_output_dim = hidden_dim; #encoder output dim, per direction, so total will be twice as large

#=========FREDA=========
local use_freda = 0; #0 = no, 1 = yes
#=======================

local final_encoder_output_dim = 2 * encoder_output_dim + use_freda * 2 * encoder_output_dim; #freda again doubles output dimension

#============TASKS==============
local my_task = "DM";
local corpus_path = "example/smallDMautomata/2S/train.zip";
local sdp_corpus_path = "example/smallDM.sdp";
local dev_corpus_path = "example/smallDMautomata/2S/dev.zip";
local dev_sdp_corpus_path = "example/minimalDM.sdp";
#===============================

local dataset_reader =  {
        "type": "amconll_automata",
         "token_indexers": {
            "tokens": {
              "type": "single_id",
              "lowercase_tokens": true
            }
        }
    };

local data_iterator = {
        "type": "same_formalism",
        "batch_size": 2,
        "formalisms" : [my_task]
    };

	
# copied from configs/task_models.libsonnet and adapted
local task_model(name,dataset_reader, data_iterator, final_encoder_output_dim, edge_model, edge_loss, label_loss) = {
    "name" : name,
    "dropout": 0.0,

    "output_null_lex_label" : true,

    "edge_model" : {
            "type" : edge_model, #e.g. "kg_edges",
            "encoder_dim" : final_encoder_output_dim,
            "label_dim": hidden_dim,
            "edge_dim": hidden_dim,
            #"activation" : "tanh",
            #"dropout": 0.0,
            "edge_label_namespace" : name+"_head_tags"
        },
         "supertagger" : {
            "mlp" : {
                "input_dim" : final_encoder_output_dim,
                "num_layers" : 1,
                "hidden_dims" : [hidden_dim],
                "dropout" : [0],
                "activations" : "tanh"
            },
            "label_namespace": name+"_supertag_labels"

        },
        "lexlabeltagger" : {
            "mlp" : {
                "input_dim" : final_encoder_output_dim,
                "num_layers" : 1,
                "hidden_dims" : [hidden_dim],
                "dropout" : [0],
                "activations" : "tanh"
            },
            "label_namespace":name+"_lex_labels"

        },

        #LOSS:
        "loss_mixing" : {
            "edge_existence" : 1.0,
            "supertagging": 1.0,
            "lexlabel": 1.0
        },
        "loss_function" : {
            "existence_loss" : { "type" : edge_loss, "normalize_wrt_seq_len": false}, #e.g. kg_edge_loss
            "label_loss" : {"type" : "dm_label_loss" , "normalize_wrt_seq_len": false} #TODO: remove dirty hack
        },

        "supertagger_loss" : { "normalize_wrt_seq_len": false },
        "lexlabel_loss" : { "normalize_wrt_seq_len": false },

        "validation_evaluator": {
			"type": "standard_evaluator",
			"formalism" : my_task,
			"system_input" : dev_corpus_path,
			"gold_file": dev_sdp_corpus_path,
			"use_from_epoch" : 200,
			"predictor" : {
                "type" : "amconll_automata_predictor",
                "dataset_reader" : dataset_reader, #same dataset_reader as above.
                "data_iterator" : data_iterator, #same bucket iterator also for validation.
                "k" : 6,
                "threads" : 1,
                "give_up": 15,
                "evaluation_command" : eval_commands['commands'][my_task]
			}
		},
};
	
	
	
	
{
    "dataset_reader": dataset_reader,
    "iterator": data_iterator,
     "vocabulary" : {
            "min_count" : {
            "lemmas" : 7,
            "words" : 7
     }
     },
    "model": {
        "type": "graph_dependency_parser_automata",

        "tasks" : [task_model(my_task, dataset_reader, data_iterator, final_encoder_output_dim, "kg_edges","kg_edge_loss","kg_label_loss")],

        "input_dropout": 0.0,
        "encoder": {
            "type" : if use_freda == 1 then "freda_split" else "shared_split_encoder",
            "formalisms" : [my_task],
			"formalisms_without_tagging": [],
            "task_dropout" : 0.0, #only relevant for freda
            "encoder": {
                "type": "stacked_bidirectional_lstm",
                "num_layers": 2, #TWO LAYERS, we don't use sesame street.
                "recurrent_dropout_probability": 0.0,
                "layer_dropout_probability": 0.0,
                "use_highway": false,
                "hidden_size": hidden_dim,
                "input_size": word_dim + pos_dim + lemma_dim + ner_dim
            }
        },

        "pos_tag_embedding":  {
           "embedding_dim": pos_dim,
           "vocab_namespace": "pos"
        },
        "lemma_embedding":  {
           "embedding_dim": lemma_dim,
           "vocab_namespace": "lemmas"
        },
         "ne_embedding":  {
           "embedding_dim": ner_dim,
           "vocab_namespace": "ner_labels"
        },

        "text_field_embedder": {
            "tokens": {
                    "type": "embedding",
                    "embedding_dim": word_dim
                },
        },

    },
    "train_data_path": [ [my_task, corpus_path]],
    "validation_data_path": [ [my_task, dev_corpus_path]],


    #=========================EVALUATE ON TEST=================================
    "evaluate_on_test" : false,
    "test_evaluators" : [],
    #==========================================================================

    "trainer": {
        "type" : "am-trainer",
        "num_epochs": num_epochs,
        "patience" : patience,
        "optimizer": {
            "type": "adam",
			"lr": lr,
        },
        "validation_metric" : eval_commands['metric_names'][my_task],
		"num_serialized_models_to_keep" : 1
		}
}
